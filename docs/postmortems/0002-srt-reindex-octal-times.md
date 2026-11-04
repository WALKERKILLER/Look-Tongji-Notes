# Rebuilt transcripts moved cues in minutes and seconds 08 and 09

Artifact-Version: 1

## Executive summary

Subtitles in some lectures showed up seconds or minutes away from the speech. The cause was `library.ParseSRT`, which read the clock fields of `transcript.srt` with `fmt.Sscan`. `Sscan` takes a leading zero as an octal prefix, so `08` and `09` read as 0. The bug escaped because the transcription path writes segments straight to the index, and only a rebuild from files read the SRT back. No test round-tripped what `SaveTranscript` writes. The lesson: a parser for data this program itself writes needs a write-then-read round-trip test over the whole value range.

## Summary

`SaveTranscript` writes `transcript.srt` correctly and indexes the same segments directly. When the index is rebuilt from the library files (`Reindex`, which runs after every WebDAV sync pull and from the rebuild-index action), cues were re-read through `ParseSRT`. Every clock whose minutes or seconds were `08` or `09` lost that field. A cue at `00:01:08,100` became 1:00.1, and one ending at `00:08:01,980` became 0:01.98. Millisecond fields with a leading zero were also read as octal (`010` became 8). The SRT files on disk were never wrong.

In the user's library, every transcribed lecture longer than eight minutes had cues that ran backwards in time. There were 36–121 per lecture, roughly one at each minute boundary, and whole runs in minutes 8, 9, 18, 19 and so on. This happened regardless of transcription engine.

## Timeline

- 2026-10-14: `ParseSRT` lands with the first Look Studio commit and is used only by reindexing.
- 2026-10-23: data sync over WebDAV starts calling `Reindex` after each pull, so synced libraries rebuild segments from SRT routinely.
- 2026-11-03:
  - The user reports some subtitles out of place.
  - Testing ruled out chunked-ASR cutting: `ffmpeg -ss … -c copy` on the VBR mp3 placed a test tone exactly.
  - Comparing the index with `transcript.srt` showed the files were right and the indexed times were not.
  - The parser was fixed, and lookd now re-reads affected transcripts at start.

## Root cause

`fmt.Sscan` into an `int64` with the `%v` verb accepts base prefixes, so `"08"` is an invalid octal literal that stops after the `0`. The parser used it on fixed-width, zero-padded decimal fields, where `strconv.ParseInt(s, 10, 64)` is the correct tool. The only tests of reindexing used clocks that avoided 08 and 09, so they passed. Nothing compared a rebuilt index with the one written at transcription time.

## Guardrails

- [`TestSRTRoundTripsEveryClock`](../../lookd/internal/library/srt_test.go) writes cues across three hours with the same formatter as `SaveTranscript` and requires `ParseSRT` to read every one back unchanged. [`TestParseSRTReadsLeadingZerosAsDecimal`](../../lookd/internal/library/srt_test.go) pins the 08/09 and short-fraction cases.
- [`TestRepairTranscriptsRereadsMisplacedCues`](../../lookd/internal/library/srt_test.go) covers `Library.RepairTranscripts`. At startup it finds lectures whose indexed cues run backwards (`Store.DisorderedTranscripts`) and re-reads their SRT, so libraries indexed by the old parser heal without user action.
