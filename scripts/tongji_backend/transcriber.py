"""Speech-to-text using BcutASR (Bilibili free cloud ASR) with SRT output.

Downloads audio via ffmpeg to a temp file, uploads to Bilibili's
cloud ASR, and polls for the result. Returns both plain text and
SRT-formatted subtitles with timestamps.
"""

import json
import os
import subprocess
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Optional

import requests

from . import config

# BcutASR API endpoints
API_BASE_URL = "https://member.bilibili.com/x/bcut/rubick-interface"
API_REQ_UPLOAD = API_BASE_URL + "/resource/create"
API_COMMIT_UPLOAD = API_BASE_URL + "/resource/create/complete"
API_CREATE_TASK = API_BASE_URL + "/task"
API_QUERY_RESULT = API_BASE_URL + "/task/result"

BCUT_HEADERS = {
    "User-Agent": "Bilibili/1.0.0 (https://www.bilibili.com)",
    "Content-Type": "application/json",
}


class TranscriptionError(RuntimeError):
    """Raised when transcription fails after all retries."""


class NoAudioStreamError(RuntimeError):
    """Raised when the media contains no audio stream."""


def _format_srt_time(ms: int) -> str:
    """Format milliseconds to SRT timestamp: HH:MM:SS,mmm"""
    hours = ms // 3600000
    minutes = (ms % 3600000) // 60000
    seconds = (ms % 60000) // 1000
    millis = ms % 1000
    return f"{hours:02d}:{minutes:02d}:{seconds:02d},{millis:03d}"


class BcutASRClient:
    """Bilibili Bcut ASR client — uploads audio and polls for transcript."""

    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update(BCUT_HEADERS)

    def transcribe_file(self, audio_path: str) -> tuple[str, str, list[dict]]:
        """Transcribe a local audio file using BcutASR.

        Returns:
            (plain_text, srt_content, utterances)
            - plain_text: joined transcript text
            - srt_content: SRT-formatted subtitles
            - utterances: raw utterance data with timestamps
        """
        with open(audio_path, "rb") as f:
            file_binary = f.read()

        if not file_binary:
            raise TranscriptionError("Audio file is empty")

        # Step 1: Request upload authorization
        payload = json.dumps({
            "type": 2,
            "name": "audio.mp3",
            "size": len(file_binary),
            "ResourceFileType": "mp3",
            "model_id": "8",
        })
        resp = self.session.post(API_REQ_UPLOAD, data=payload)
        resp.raise_for_status()
        resp_data = resp.json()["data"]

        in_boss_key = resp_data["in_boss_key"]
        resource_id = resp_data["resource_id"]
        upload_id = resp_data["upload_id"]
        upload_urls = resp_data["upload_urls"]
        per_size = resp_data["per_size"]
        clips = len(upload_urls)

        # Step 2: Upload audio in parts
        etags = []
        for clip_idx in range(clips):
            start = clip_idx * per_size
            end = (clip_idx + 1) * per_size
            part_resp = requests.put(
                upload_urls[clip_idx],
                data=file_binary[start:end],
                headers=BCUT_HEADERS,
            )
            part_resp.raise_for_status()
            etag = part_resp.headers.get("Etag")
            if etag:
                etags.append(etag)

        # Step 3: Commit upload
        commit_data = json.dumps({
            "InBossKey": in_boss_key,
            "ResourceId": resource_id,
            "Etags": ",".join(etags) if etags else "",
            "UploadId": upload_id,
            "model_id": "8",
        })
        resp = self.session.post(API_COMMIT_UPLOAD, data=commit_data)
        resp.raise_for_status()
        download_url = resp.json()["data"]["download_url"]

        # Step 4: Create ASR task
        resp = self.session.post(
            API_CREATE_TASK,
            json={"resource": download_url, "model_id": "8"},
        )
        resp.raise_for_status()
        task_id = resp.json()["data"]["task_id"]

        # Step 5: Poll for result
        for _ in range(600):
            resp = self.session.get(
                API_QUERY_RESULT,
                params={"model_id": 7, "task_id": task_id},
            )
            resp.raise_for_status()
            task_resp = resp.json()["data"]

            if task_resp["state"] == 4:
                result = json.loads(task_resp["result"])
                utterances = result.get("utterances", [])

                # Build plain text
                texts = [u.get("transcript", "") for u in utterances]
                plain_text = " ".join(texts)

                # Build SRT content
                srt_parts = []
                for idx, u in enumerate(utterances, 1):
                    start_ms = u.get("start_time", 0)
                    end_ms = u.get("end_time", 0)
                    text = u.get("transcript", "").strip()
                    if text:
                        srt_parts.append(
                            f"{idx}\n"
                            f"{_format_srt_time(start_ms)} --> {_format_srt_time(end_ms)}\n"
                            f"{text}\n"
                        )
                srt_content = "\n".join(srt_parts)

                return plain_text, srt_content, utterances

            if task_resp["state"] in (-1, 5):
                raise TranscriptionError(
                    f"ASR task failed with state={task_resp['state']}"
                )

            time.sleep(1)

        raise TranscriptionError("ASR task timed out (10 min)")


class Transcriber:
    """ASR transcriber using BcutASR with retry mechanism."""

    def __init__(self):
        self._asr = None
        self._last_transcript = ""
        self._last_duration = 0.0

    def _get_asr(self) -> BcutASRClient:
        if self._asr is None:
            self._asr = BcutASRClient()
        return self._asr

    def _download_audio(self, url: str, http_headers: str = None,
                        timeout: int = 600) -> str:
        """Download audio from URL to a temp MP3 file using ffmpeg.

        Uses parallel chunk downloading for large files, then extracts audio.
        Falls back to single-stream ffmpeg if range requests aren't supported.
        """
        tmp_dir = tempfile.mkdtemp(prefix="tongji_asr_")
        output_path = os.path.join(tmp_dir, "audio.mp3")

        # Try parallel download first
        try:
            downloaded = self._parallel_download(url, http_headers, tmp_dir, timeout)
            if downloaded:
                # Extract audio from the downloaded file
                self._extract_audio(downloaded, output_path, timeout)
                # Clean up the raw download
                if downloaded != output_path and os.path.exists(downloaded):
                    try:
                        os.remove(downloaded)
                    except Exception:
                        pass
                if os.path.exists(output_path) and os.path.getsize(output_path) > 0:
                    size_mb = os.path.getsize(output_path) / (1024 * 1024)
                    print(f"[Transcriber] Downloaded (parallel) {size_mb:.1f}MB")
                    return output_path
        except Exception as e:
            print(f"[Transcriber] Parallel download failed, falling back: {e}")

        # Fallback: single-stream ffmpeg download + extract
        cmd = ["ffmpeg"]
        if http_headers:
            cmd += ["-headers", http_headers]
        cmd += [
            "-reconnect", "1",
            "-reconnect_streamed", "1",
            "-reconnect_delay_max", "5",
            "-i", url,
            "-vn",
            "-ar", "16000", "-ac", "1",
            "-acodec", "libmp3lame", "-q:a", "4",
            "-y", output_path,
        ]

        print(f"[Transcriber] Downloading audio to {output_path}...")
        t0 = time.time()

        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, timeout=timeout,
            )
        except subprocess.TimeoutExpired:
            raise TranscriptionError(f"Audio download timed out after {timeout}s")

        elapsed = time.time() - t0

        if not os.path.exists(output_path) or os.path.getsize(output_path) == 0:
            if result.stderr and "does not contain any stream" in result.stderr:
                raise NoAudioStreamError("No audio stream found in media")
            raise TranscriptionError(
                f"ffmpeg failed (code={result.returncode}): "
                f"{result.stderr[-500:] if result.stderr else 'no stderr'}"
            )

        size_mb = os.path.getsize(output_path) / (1024 * 1024)
        print(f"[Transcriber] Downloaded {size_mb:.1f}MB in {elapsed:.0f}s")
        return output_path

    def _parallel_download(self, url: str, http_headers: str = None,
                           tmp_dir: str = None, timeout: int = 600) -> str | None:
        """Download video file using parallel HTTP range requests.

        Returns path to downloaded file, or None if server doesn't support ranges.
        """
        if not tmp_dir:
            tmp_dir = tempfile.mkdtemp(prefix="tongji_asr_")

        headers = {}
        if http_headers:
            for line in http_headers.strip().split("\r\n"):
                if ": " in line:
                    k, v = line.split(": ", 1)
                    headers[k] = v

        # Check if server supports range requests
        head_resp = requests.head(url, headers=headers, timeout=15, allow_redirects=True)
        accept_ranges = head_resp.headers.get("Accept-Ranges", "").lower()
        content_length = int(head_resp.headers.get("Content-Length", 0))

        if not content_length or accept_ranges == "none":
            print("[Transcriber] Server doesn't support range requests")
            return None

        # Determine chunk size and number of threads
        num_threads = min(8, max(1, content_length // (2 * 1024 * 1024)))  # 2MB per thread min
        chunk_size = content_length // num_threads

        print(f"[Transcriber] Parallel download: {content_length / 1024 / 1024:.1f}MB "
              f"with {num_threads} threads")

        chunk_files = [None] * num_threads
        t0 = time.time()

        def download_chunk(idx: int, start: int, end: int):
            chunk_headers = {**headers, "Range": f"bytes={start}-{end}"}
            chunk_path = os.path.join(tmp_dir, f"chunk_{idx}.tmp")
            resp = requests.get(url, headers=chunk_headers, timeout=timeout, stream=True)
            resp.raise_for_status()
            with open(chunk_path, "wb") as f:
                for block in resp.iter_content(chunk_size=65536):
                    f.write(block)
            chunk_files[idx] = chunk_path

        # Download chunks in parallel
        with ThreadPoolExecutor(max_workers=num_threads) as executor:
            futures = []
            for i in range(num_threads):
                start = i * chunk_size
                end = (i + 1) * chunk_size - 1 if i < num_threads - 1 else content_length - 1
                futures.append(executor.submit(download_chunk, i, start, end))

            for future in as_completed(futures):
                try:
                    future.result()
                except Exception as e:
                    print(f"[Transcriber] Chunk download failed: {e}")
                    raise

        # Merge chunks
        merged_path = os.path.join(tmp_dir, "video_raw.tmp")
        with open(merged_path, "wb") as out_f:
            for chunk_path in chunk_files:
                if chunk_path and os.path.exists(chunk_path):
                    with open(chunk_path, "rb") as in_f:
                        while True:
                            block = in_f.read(65536)
                            if not block:
                                break
                            out_f.write(block)
                    try:
                        os.remove(chunk_path)
                    except Exception:
                        pass

        elapsed = time.time() - t0
        size_mb = os.path.getsize(merged_path) / (1024 * 1024)
        print(f"[Transcriber] Parallel download: {size_mb:.1f}MB in {elapsed:.0f}s")

        return merged_path

    def _extract_audio(self, input_path: str, output_path: str,
                       timeout: int = 300):
        """Extract and compress audio from a video file using ffmpeg."""
        cmd = [
            "ffmpeg",
            "-i", input_path,
            "-vn",
            "-ar", "16000", "-ac", "1",
            "-acodec", "libmp3lame", "-q:a", "4",
            "-y", output_path,
        ]
        print(f"[Transcriber] Extracting audio from {input_path}...")
        t0 = time.time()

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

        elapsed = time.time() - t0
        if not os.path.exists(output_path) or os.path.getsize(output_path) == 0:
            if result.stderr and "does not contain any stream" in result.stderr:
                raise NoAudioStreamError("No audio stream found in media")
            raise TranscriptionError(
                f"ffmpeg extract failed (code={result.returncode}): "
                f"{result.stderr[-500:] if result.stderr else 'no stderr'}"
            )

        size_mb = os.path.getsize(output_path) / (1024 * 1024)
        print(f"[Transcriber] Audio extracted: {size_mb:.1f}MB in {elapsed:.0f}s")

    def transcribe_url(self, url: str, timeout: int = 7200,
                       http_headers: str = None) -> tuple[str, str, list[dict]]:
        """Stream audio from URL, transcribe with BcutASR.

        Returns:
            (plain_text, srt_content, utterances)
        """
        max_retries = config.MAX_ASR_RETRIES
        backoff_base = config.ASR_RETRY_BACKOFF
        asr = self._get_asr()

        last_error = None
        for attempt in range(1, max_retries + 1):
            tmp_path = None
            try:
                print(f"[Transcriber] Attempt {attempt}/{max_retries}")
                tmp_path = self._download_audio(url, http_headers)

                t0 = time.time()
                plain_text, srt_content, utterances = asr.transcribe_file(tmp_path)
                elapsed = time.time() - t0

                if not plain_text or not plain_text.strip():
                    raise TranscriptionError("ASR returned empty transcript")

                self._last_transcript = plain_text
                print(f"[Transcriber] Success: {len(plain_text)} chars in {elapsed:.0f}s")
                return plain_text, srt_content, utterances

            except NoAudioStreamError:
                raise

            except Exception as e:
                last_error = e
                print(f"[Transcriber] Attempt {attempt}/{max_retries} failed: {e}")
                if attempt < max_retries:
                    wait = backoff_base * (2 ** (attempt - 1))
                    print(f"[Transcriber] Retrying in {wait}s...")
                    time.sleep(wait)

            finally:
                if tmp_path and os.path.exists(tmp_path):
                    try:
                        os.remove(tmp_path)
                        tmp_dir = os.path.dirname(tmp_path)
                        if not os.listdir(tmp_dir):
                            os.rmdir(tmp_dir)
                    except Exception:
                        pass

        raise TranscriptionError(
            f"Transcription failed after {max_retries} attempts. "
            f"Last error: {type(last_error).__name__}: {last_error}"
        )
