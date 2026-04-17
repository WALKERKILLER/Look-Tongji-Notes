"""Tongji University look.tongji.edu.cn authentication.

Uses Playwright browser automation to complete the IAM SSO login flow,
which requires RSA-encrypted password submission and JavaScript-driven
OAuth2 authorization. After login, the JWT token is extracted from the
_token cookie and used for all subsequent API requests via Bearer auth.
"""

import re

import requests

from . import config


def _extract_jwt_from_token_cookie(cookie_value: str) -> str | None:
    """Extract JWT from the PHP-serialized _token cookie.

    Cookie format: hash:2:{i:0;s:6:"_token";i:1;s:NNN:"JWT_HERE";}
    """
    match = re.search(r's:\d+:"(eyJ[^"]+)"', cookie_value)
    if match:
        return match.group(1)
    if cookie_value.startswith("eyJ"):
        return cookie_value
    return None


def _playwright_login(username: str, password: str) -> str:
    """Login via Playwright browser automation and return JWT token."""
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        raise RuntimeError(
            "Playwright is required for Tongji SSO login. "
            "Install it with: pip install playwright && playwright install chromium"
        )

    jwt_token = None

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context()
        page = context.new_page()

        try:
            print("[Auth] Opening browser for SSO login...")
            sso_url = (
                f"{config.TONGJI_BASE_URL}/casapi/index.php"
                f"?r=auth/login&auType=&tenant_code={config.TONGJI_TENANT_CODE}"
                f"&forward={config.TONGJI_BASE_URL}/validate"
            )
            page.goto(sso_url, wait_until="networkidle", timeout=30000)

            username_input = page.locator("#j_username")
            password_input = page.locator("#j_password")

            if username_input.count() == 0 or password_input.count() == 0:
                raise RuntimeError("IAM login form not found on page")

            username_input.fill(username)
            password_input.fill(password)

            login_button = page.locator("#loginButton")
            if login_button.count() > 0:
                login_button.click()
            else:
                password_input.press("Enter")

            page.wait_for_url(f"{config.TONGJI_BASE_URL}/**", timeout=30000)
            page.wait_for_timeout(2000)

            cookies = context.cookies()
            token_cookie = None
            for c in cookies:
                if c["name"] == "_token":
                    token_cookie = c["value"]
                    break

            if token_cookie:
                decoded = _decode_uri_component(token_cookie) if "%" in token_cookie else token_cookie
                jwt_token = _extract_jwt_from_token_cookie(decoded)

            if not jwt_token:
                current_url = page.url
                if "iam" in current_url:
                    error_text = page.locator(".tabCon").inner_text()
                    raise RuntimeError(f"IAM login failed: {error_text.strip()}")
                raise RuntimeError("Login completed but no JWT token found")

            print("[Auth] Browser login successful!")

        finally:
            context.close()
            browser.close()

    return jwt_token


def _decode_uri_component(s: str) -> str:
    """Decode percent-encoded string."""
    import urllib.parse
    return urllib.parse.unquote(s)


class TongjiAuth:
    """Manages authentication for look.tongji.edu.cn via Tongji IAM SSO.

    Uses Playwright for browser-based SSO login, then switches to
    requests.Session with Bearer token for API calls.
    """

    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": config.USER_AGENT,
        })
        self.jwt_token: str | None = None
        self.logged_in = False
        self._userinfo: dict | None = None

    def login(self, username: str = None, password: str = None) -> bool:
        """Login via iam.tongji.edu.cn SSO.

        Returns True on success, raises on failure.
        """
        username = username or config.TONGJI_USERNAME
        password = password or config.TONGJI_PASSWORD

        if not username or not password:
            raise ValueError(
                "Tongji username and password required. "
                "Set TONGJI_USERNAME and TONGJI_PASSWORD environment variables."
            )

        print("[Auth] Logging in to look.tongji.edu.cn...")

        try:
            self.jwt_token = _playwright_login(username, password)
        except RuntimeError:
            raise
        except Exception as e:
            raise RuntimeError(f"Playwright login failed: {e}") from e

        if not self.jwt_token:
            raise RuntimeError("Login completed but no JWT token obtained")

        self._setup_bearer_auth()
        self.logged_in = True
        self._userinfo = None  # Reset cache
        print(f"[Auth] Login successful! Token: {self.jwt_token[:30]}...")
        return True

    def _setup_bearer_auth(self):
        """Configure session headers with Bearer token for API requests."""
        if self.jwt_token:
            self.session.headers.update({
                "Authorization": f"Bearer {self.jwt_token}",
                "accept-language": "zh_cn",
            })

    def check_alive(self) -> bool:
        """Quick session health check by calling user info API."""
        if not self.jwt_token:
            return False

        try:
            resp = self.session.get(
                f"{config.TONGJI_BASE_URL}/userapi/v1/infosimple",
                timeout=10,
            )
            if resp.status_code == 200:
                try:
                    data = resp.json()
                    if data.get("code") in (0, 200, "0", "200"):
                        return True
                except Exception:
                    pass

            if resp.status_code in (401, 403):
                return False

            return resp.status_code == 200
        except Exception:
            return False

    def get_jwt_token(self) -> str | None:
        """Return the JWT Bearer token string."""
        return self.jwt_token

    def get_session(self) -> requests.Session:
        """Return the authenticated requests session with Bearer token."""
        return self.session

    def get_userinfo(self) -> dict:
        """Get current user info from the platform API."""
        if self._userinfo is not None:
            return self._userinfo

        try:
            resp = self.session.get(
                f"{config.TONGJI_BASE_URL}/userapi/v1/infosimple",
                timeout=15,
            )
            if resp.status_code == 200:
                data = resp.json()
                if data.get("code") in (0, 200, "0", "200"):
                    self._userinfo = data.get("params") or data.get("data", {})
                    return self._userinfo
        except Exception:
            pass

        self._userinfo = {}
        return self._userinfo
