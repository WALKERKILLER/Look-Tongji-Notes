package fudan

import (
	"context"
	"net/http"
	"net/url"
)

// ICourseBase is Fudan's lecture-recording platform, reachable only on campus
// or through WebVPN. It is the product Tongji runs as Look (the same
// courseapi and media signing), so lookd's Look client serves both.
const ICourseBase = "https://icourse.fudan.edu.cn"

// SignInICourse signs in to WebVPN and then, through the gateway, to iCourse.
// hc must carry a cookie jar: afterwards it holds the gateway's session
// cookie, and the gateway keeps iCourse's cookies for that session. With an
// empty password it succeeds only while the UIS session lasts.
func SignInICourse(ctx context.Context, hc *http.Client, username, password string) error {
	if err := (&UIS{HC: hc}).Login(ctx, WebVPNBase+"/login?cas_login=true", username, password); err != nil {
		return err
	}
	start, err := VPNURL(ICourseBase + "/casapi/index.php?r=auth/login&school_login=1&tenant_code=222&forward=" + url.QueryEscape(ICourseBase+"/"))
	if err != nil {
		return err
	}
	return (&UIS{HC: hc, VPN: true, Entity: ICourseBase}).Login(ctx, start, username, password)
}
