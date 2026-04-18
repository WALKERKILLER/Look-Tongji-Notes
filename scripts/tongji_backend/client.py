"""Tongji University look.tongji.edu.cn API client.

Provides access to course details, lecture lists, and video URLs
on the Tongji course recording platform. Uses JWT Bearer token
authentication obtained via iam.tongji.edu.cn SSO.
"""

import hashlib
import json
import time
import uuid
from urllib.parse import urlparse

import requests

from . import config
from .auth import TongjiAuth


class TongjiClient:
    """Client for the Tongji look platform API with Bearer token auth."""

    def __init__(self, auth: TongjiAuth):
        self.auth = auth
        self.session = auth.get_session()
        self.base_url = config.TONGJI_BASE_URL
        self._userinfo = None
        self._token = auth.get_jwt_token() or ""

    def get_userinfo(self) -> dict:
        """Get current user info. Caches the result for the session."""
        if self._userinfo is not None:
            return self._userinfo
        self._userinfo = self.auth.get_userinfo()
        return self._userinfo

    def check_alive(self) -> bool:
        """Quick session health check."""
        return self.auth.check_alive()

    def get_all_courses(self) -> list[dict]:
        """Get ALL courses accessible to the current user.

        Uses multiple APIs to enumerate every course:
        1. account-profile/course (primary, most complete - "我的课程")
        2. recent-learning (supplementary)
        3. term-years + schedule (supplementary)

        Returns list of {course_id, title, teacher}.
        """
        courses = []
        seen_ids = set()

        # 1. Primary: account-profile/course API (most complete, returns ALL enrolled courses)
        try:
            page_num = 1
            per_page = 100
            while True:
                resp = self.session.get(
                    f"{self.base_url}/personal/courseapi/vlabpassportapi/v1/account-profile/course",
                    params={"nowpage": page_num, "per-page": per_page},
                    timeout=15,
                )
                if resp.status_code == 200:
                    data = resp.json()
                    # Response: {code: 1000, params: {result: {data: [...], total: N}}}
                    result = data.get("params", {}).get("result", {})
                    items = result.get("data", [])
                    if not items:
                        break
                    for item in items:
                        # Field names: Id, Title, Teacher (capital first letter)
                        cid = str(item.get("Id") or item.get("course_id", ""))
                        if cid and cid not in seen_ids:
                            seen_ids.add(cid)
                            courses.append({
                                "course_id": cid,
                                "title": item.get("Title") or item.get("course_title", ""),
                                "teacher": item.get("Teacher") or item.get("realname", ""),
                            })
                    # Check if there are more pages
                    total = result.get("total", 0)
                    if page_num * per_page >= total:
                        break
                    page_num += 1
                else:
                    break
        except Exception as e:
            print(f"[WARN] account-profile/course failed: {e}")

        # 2. Supplementary: recent-learning
        try:
            recent = self.get_recent_courses(per_page=200)
            for c in recent:
                cid = c["course_id"]
                if cid and cid not in seen_ids:
                    seen_ids.add(cid)
                    courses.append(c)
        except Exception:
            pass

        # 3. Supplementary: term-years + schedule
        try:
            resp = self.session.get(
                f"{self.base_url}/courseapi/v2/course/get-term-years",
                params={"tenant": config.TONGJI_TENANT_CODE},
                timeout=15,
            )
            if resp.status_code == 200:
                data = resp.json()
                term_years = data.get("data", {}).get("list", [])
            else:
                term_years = []
        except Exception as e:
            print(f"[WARN] get-term-years failed: {e}")
            term_years = []

        for ty in term_years:
            term_id = ty.get("id") or ty.get("term_id") or ty.get("year", "")
            if not term_id:
                continue
            try:
                resp = self.session.get(
                    f"{self.base_url}/courseapi/v2/schedule/get-term-schedules",
                    params={
                        "user_id": self._get_user_id(),
                        "tenant_id": config.TONGJI_TENANT_CODE,
                        "term_id": term_id,
                        "token": self._token,
                    },
                    timeout=15,
                )
                if resp.status_code == 200:
                    data = resp.json()
                    items = data.get("data", {}).get("list", [])
                    if isinstance(items, dict):
                        items = items.get("courses", [])
                    for item in items:
                        cid = str(item.get("course_id", ""))
                        if cid and cid not in seen_ids:
                            seen_ids.add(cid)
                            courses.append({
                                "course_id": cid,
                                "title": item.get("course_title", item.get("title", "")),
                                "teacher": item.get("realname", item.get("teacher", "")),
                            })
            except Exception as e:
                print(f"[WARN] get-term-schedules for {term_id} failed: {e}")

        return courses

    def _get_user_id(self) -> str:
        """Get current user's ID from JWT token payload."""
        try:
            payload = self._token.split(".")[1]
            import base64
            padded = payload + "=" * (4 - len(payload) % 4)
            data = json.loads(base64.urlsafe_b64decode(padded))
            return str(data.get("sub", ""))
        except Exception:
            return ""

    def get_recent_courses(self, page: int = 1, per_page: int = 50) -> list[dict]:
        """Get recently learned courses from the platform.

        Returns list of dicts with: course_id, course_title, sub_id, sub_title, etc.
        """
        api_url = f"{self.base_url}/courseapi/v3/o-course/recent-learning"
        params = {"page": page, "per-page": per_page}

        try:
            resp = self.session.get(api_url, params=params, timeout=30)
            if resp.status_code == 200:
                data = resp.json()
                if data.get("success") or data.get("result", {}).get("err") in (0, 200):
                    models = (
                        data.get("result", {})
                        .get("data", {})
                        .get("models", [])
                    )
                    # Deduplicate by course_id
                    seen = set()
                    courses = []
                    for m in models:
                        cid = str(m.get("course_id", ""))
                        if cid and cid not in seen:
                            seen.add(cid)
                            courses.append({
                                "course_id": cid,
                                "title": m.get("course_title", ""),
                            })
                    return courses
        except Exception as e:
            print(f"[WARN] get_recent_courses failed: {e}")

        return []

    def get_course_detail(self, course_id: str) -> dict:
        """Get course details including title, teacher, and lecture list.

        Returns dict with keys: title, teacher, lectures
        Each lecture has: sub_id, sub_title, lecturer_name, date, has_playback
        """
        api_url = f"{self.base_url}/courseapi/v3/multi-search/get-course-detail"
        params = {
            "course_id": course_id,
            "tenant_code": config.TONGJI_TENANT_CODE,
        }

        try:
            resp = self.session.get(api_url, params=params, timeout=30)
            if resp.status_code == 200:
                data = resp.json()
                if data.get("code") in (0, 200, "0", "200"):
                    return self._parse_course_detail(data)
        except Exception as e:
            print(f"    [WARN] get-course-detail API failed: {e}")

        # Fallback: try with student param
        try:
            params["student"] = config.TONGJI_USERNAME
            resp = self.session.get(api_url, params=params, timeout=30)
            if resp.status_code == 200:
                data = resp.json()
                if data.get("code") in (0, 200, "0", "200"):
                    return self._parse_course_detail(data)
        except Exception as e:
            print(f"    [WARN] get-course-detail with student param failed: {e}")

        print("    All API endpoints failed")
        return {"title": "Unknown", "teacher": "Unknown", "lectures": []}

    @staticmethod
    def _safe_int(value, default: int = 0) -> int:
        try:
            return int(value)
        except Exception:
            return default

    def _parse_ppt_item(self, item: dict) -> dict | None:
        content = item.get("content")
        if isinstance(content, str):
            try:
                content = json.loads(content)
            except Exception:
                content = {}
        if not isinstance(content, dict):
            content = {}

        image_url = str(content.get("pptimgurl") or content.get("pptthumb") or "").strip()
        if not image_url:
            return None

        created_sec = self._safe_int(
            item.get("created_sec", content.get("created", 0)),
            default=0,
        )

        return {
            "course_id": str(item.get("course_id") or "").strip(),
            "sub_id": str(item.get("sub_id") or "").strip(),
            "created_sec": created_sec,
            "image_url": image_url,
            "thumb_url": str(content.get("pptthumb") or "").strip(),
            "detecttype": str(content.get("detecttype") or "").strip(),
            "is_key": bool(content.get("is_key")),
            "raw": item,
        }

    def get_ppt_snapshots(
        self,
        course_id: str,
        sub_id: str,
        *,
        per_page: int = 100,
        max_pages: int = 20,
    ) -> list[dict]:
        """List PPT snapshot metadata for one lecture."""
        api_url = f"{self.base_url}/pptnote/v1/schedule/search-ppt"
        per_page = max(1, int(per_page))
        max_pages = max(1, int(max_pages))

        snapshots: list[dict] = []
        seen: set[tuple[int, str]] = set()
        total_hint = 0

        for page in range(1, max_pages + 1):
            params = {
                "course_id": course_id,
                "sub_id": sub_id,
                "page": page,
                "per_page": per_page,
            }
            resp = self.session.get(api_url, params=params, timeout=30)
            if resp.status_code != 200:
                raise RuntimeError(f"search-ppt failed (HTTP {resp.status_code})")

            data = resp.json()
            code = data.get("code")
            if code not in (0, 200, "0", "200"):
                raise RuntimeError(f"search-ppt failed (code={code}, msg={data.get('msg', '')})")

            items = data.get("list") or []
            total_hint = max(total_hint, self._safe_int(data.get("total"), default=0))
            added = 0

            for item in items:
                if not isinstance(item, dict):
                    continue
                parsed = self._parse_ppt_item(item)
                if not parsed:
                    continue
                key = (parsed["created_sec"], parsed["image_url"])
                if key in seen:
                    continue
                seen.add(key)
                snapshots.append(parsed)
                added += 1

            if added == 0:
                break
            if total_hint and len(snapshots) >= total_hint:
                break
            if len(items) < per_page:
                break

        snapshots.sort(key=lambda x: (x.get("created_sec", 0), x.get("image_url", "")))
        return snapshots

    def _parse_course_detail(self, data: dict) -> dict:
        """Parse course detail from API response."""
        course_data = data.get("data", {})
        title = course_data.get("title", "Unknown")
        teacher = course_data.get("realname", course_data.get("teacher", "Unknown"))

        lectures = []
        sub_list = course_data.get("sub_list", {})

        # Handle nested date structure: {year: {month: {day: [items]}}}
        if isinstance(sub_list, dict):
            for year, months in sub_list.items():
                for month, days in months.items():
                    for day, items in days.items():
                        if isinstance(items, list):
                            for item in items:
                                if isinstance(item, dict) and "id" in item:
                                    lectures.append({
                                        "sub_id": item["id"],
                                        "sub_title": item.get("sub_title", ""),
                                        "lecturer_name": item.get("lecturer_name", ""),
                                        "date": f"{year}-{month}-{day}",
                                        "has_playback": str(item.get("playback_status")) == "1",
                                    })
        # Handle flat list structure
        elif isinstance(sub_list, list):
            for item in sub_list:
                if isinstance(item, dict) and "id" in item:
                    lectures.append({
                        "sub_id": item["id"],
                        "sub_title": item.get("sub_title", ""),
                        "lecturer_name": item.get("lecturer_name", ""),
                        "date": item.get("date", ""),
                        "has_playback": str(item.get("playback_status")) == "1",
                    })

        # Also check data.list or data.lectures
        if not lectures:
            items = course_data.get("list", course_data.get("lectures", []))
            if isinstance(items, list):
                for item in items:
                    if isinstance(item, dict):
                        lectures.append({
                            "sub_id": item.get("id", item.get("sub_id", "")),
                            "sub_title": item.get("sub_title", item.get("title", "")),
                            "lecturer_name": item.get("lecturer_name", ""),
                            "date": item.get("date", ""),
                            "has_playback": (
                                str(item.get("playback_status", "")) == "1"
                                or item.get("has_playback", False)
                            ),
                        })

        return {"title": title, "teacher": teacher, "lectures": lectures}

    def get_video_url(self, course_id: str, sub_id: str) -> str | None:
        """Get a signed video URL for a specific lecture."""
        # Primary: get-sub-info API
        api_url = f"{self.base_url}/courseapi/v3/portal-home-setting/get-sub-info"
        params = {
            "course_id": course_id,
            "sub_id": sub_id,
            "tenant_code": config.TONGJI_TENANT_CODE,
        }

        try:
            resp = self.session.get(api_url, params=params, timeout=30)
            if resp.status_code == 200:
                data = resp.json()
                if data.get("code") in (0, 200, "0", "200"):
                    video_url = self._extract_video_url(data.get("data", {}))
                    if video_url:
                        return video_url
        except Exception as e:
            print(f"    [WARN] get-sub-info API failed: {e}")

        # Fallback: get-sub-detail API
        detail_url = f"{self.base_url}/courseapi/v3/multi-search/get-sub-detail"
        try:
            resp = self.session.get(detail_url, params=params, timeout=30)
            if resp.status_code == 200:
                data = resp.json()
                if data.get("code") in (0, 200, "0", "200"):
                    content = data.get("data", {}).get("content", {})
                    playback = content.get("playback", {})
                    if playback and playback.get("url"):
                        return playback["url"]
        except Exception as e:
            print(f"    [WARN] get-sub-detail API failed: {e}")

        return None

    def _extract_video_url(self, info: dict) -> str | None:
        """Extract video URL from sub-info response data."""
        base_url = None

        # Try video_list first
        video_list = info.get("video_list", {})
        if isinstance(video_list, dict):
            for _, v in video_list.items():
                if isinstance(v, dict):
                    preview = v.get("preview_url")
                    if preview and (preview.endswith(".mp4") or preview.endswith(".m3u8")):
                        base_url = preview
                        break

        # Fallback: try playurl dict
        if not base_url:
            playurl = info.get("playurl", {})
            if isinstance(playurl, dict):
                for k, v in playurl.items():
                    if k == "now":
                        continue
                    if isinstance(v, str) and (v.endswith(".mp4") or v.endswith(".m3u8")):
                        base_url = v
                        break

        # Fallback: try url field directly
        if not base_url:
            base_url = info.get("url") or info.get("video_url") or info.get("play_url")

        # Sign URL with CDN auth
        if base_url and "clientUUID" not in base_url:
            try:
                base_url = self._sign_video_url(base_url, info.get("now"))
            except Exception:
                pass

        return base_url

    def _sign_video_url(self, video_url: str, now=None) -> str:
        """Sign a video URL with CDN authentication."""
        userinfo = self.get_userinfo()
        if not userinfo:
            return video_url

        user_id = userinfo.get("id", "")
        tenant_id = userinfo.get("tenant_id", "")
        phone = str(userinfo.get("phone", ""))

        if now is None:
            now = int(time.time())
        elif isinstance(now, str):
            now = int(now)

        reversed_phone = phone[::-1]
        pathname = urlparse(video_url).path
        hash_input = f"{pathname}{user_id}{tenant_id}{reversed_phone}{now}"
        md5_hash = hashlib.md5(hash_input.encode()).hexdigest()
        t_param = f"{user_id}-{now}-{md5_hash}"

        client_uuid = str(uuid.uuid4())
        sep = "&" if "?" in video_url else "?"
        return f"{video_url}{sep}clientUUID={client_uuid}&t={t_param}"

    def get_stream_params(self, video_url: str) -> tuple[str, str]:
        """Get URL and HTTP headers for direct streaming.

        Returns:
            (url, http_headers) where http_headers is ffmpeg-compatible.
        """
        cookies = "; ".join(
            f"{c.name}={c.value}" for c in self.session.cookies
        )
        headers = f"Cookie: {cookies}\r\nUser-Agent: {config.USER_AGENT}\r\n"
        return video_url, headers
