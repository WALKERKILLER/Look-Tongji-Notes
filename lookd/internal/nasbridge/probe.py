"""Read-only deployment adapter; stdout contains only the explicit public schema."""
import datetime, json, sqlite3, subprocess
from pathlib import Path

root = Path.home() / '.local/share/course-homework-worker'
out = {'schema_version': 1, 'source': 'nas', 'observed_at': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'jobs': [], 'services': []}
for name, unit, health in [('homework', 'course-homework', 'health.json'), ('calendar', 'course-calendar-nightly', 'calendar-health.json')]:
    d = json.loads((root / health).read_text())
    def props(suffix, fields):
        p = subprocess.run(['systemctl', '--user', 'show', unit + suffix, *['--property=' + f for f in fields]], capture_output=True, text=True, timeout=5)
        if p.returncode: raise RuntimeError('service observation failed')
        return dict(line.split('=', 1) for line in p.stdout.splitlines() if '=' in line)
    s = props('.service', ['ActiveState', 'Result'])
    t = props('.timer', ['NextElapseUSecRealtime', 'ActiveState'])
    out['services'].append({'id': name, 'active': s.get('ActiveState'), 'result': s.get('Result'), 'timer_active': t.get('ActiveState'), 'next_run': t.get('NextElapseUSecRealtime'), 'health': {k: d[k] for k in ['started','finished','discovery_ok','calendar_ok','jobs','failures','calendar_triggered'] if k in d}})
c = sqlite3.connect('file:' + str(root / 'queue.sqlite3') + '?mode=ro', uri=True, timeout=5)
for key, task, status, attempts, updated, error in c.execute('SELECT key,task,status,attempts,updated,error FROM jobs ORDER BY updated DESC LIMIT 500'):
    d = json.loads(task)
    out['jobs'].append({'id': key, 'course': d.get('course',''), 'name': d.get('name',''), 'canvas_course_id': str(d.get('course_id','')), 'assignment_id': str(d.get('assignment_id','')), 'due_at': d.get('due_at'), 'url': d.get('url',''), 'generation_state': 'not_recorded' if status == 'submitted' else status, 'worker_state': status, 'submission_state': 'submitted' if d.get('submitted') or status == 'submitted' else 'unconfirmed', 'attempts': attempts, 'updated': updated, 'reason': 'execution_timeout' if 'execution limit' in (error or '') else ('needs_attention' if error else '')})
for name in ['icourse-subscriber', 'course-calendar-sync']:
    p = subprocess.run(['docker','inspect','--format','{{.State.Status}}',name],capture_output=True,text=True,timeout=5)
    out['services'].append({'id': name, 'active': p.stdout.strip() if p.returncode == 0 else 'unknown'})
print(json.dumps(out, ensure_ascii=False))
