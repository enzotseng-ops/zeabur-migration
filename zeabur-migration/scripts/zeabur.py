#!/usr/bin/env python3
"""Zeabur GraphQL 小工具：只印 key、網域、狀態，不印環境變數的值。

用法（token 放環境變數 ZEABUR_TOKEN，或權限 600 的檔案再用 ZEABUR_TOKEN_FILE 指過去）：
  zeabur.py keys        <service_id> <env_id>              # 列出環境變數 key（唯讀）
  zeabur.py domains     <service_id> <env_id>              # 列出網域與轉址（唯讀）
  zeabur.py autorestart <service_id> <env_id>              # 查自動重啟設定（唯讀）
  zeabur.py set         <service_id> <env_id> KEY          # 新增或更新環境變數，值從標準輸入讀（寫入）
                                                           #   例：zeabur.py set SID EID MAINTENANCE_MODE <<< true
                                                           #   機密值請用 < 檔案 傳入，不要放在指令列
  zeabur.py unset       <service_id> <env_id> KEY          # 刪除環境變數（寫入）
  zeabur.py restart     <service_id> <env_id>              # 重啟服務（寫入）
  zeabur.py redirect    <service_id> <env_id> <sub> <target-host>   # <sub>.zeabur.app 改 302 到 target-host（寫入）
  zeabur.py unredirect  <service_id> <env_id> <sub>        # 取消轉址（寫入）

寫入類指令會先要求在終端機輸入 yes。設 ZEABUR_YES=1 可略過（只在使用者已經同意時用）。
欄位名稱以 2026-11 的 API 為準，Zeabur 改版時要重新確認（references/zeabur-api.md）。
"""
import json, os, sys, urllib.request

API = os.environ.get('ZEABUR_API', 'https://api.zeabur.com/graphql')


def token():
    if os.environ.get('ZEABUR_TOKEN'):
        return os.environ['ZEABUR_TOKEN'].strip()
    f = os.environ.get('ZEABUR_TOKEN_FILE')
    if f:
        with open(f) as fh:
            return fh.read().strip()
    sys.exit('set ZEABUR_TOKEN or ZEABUR_TOKEN_FILE')


def gql(query):
    req = urllib.request.Request(API, json.dumps({'query': query}).encode(),
                                 {'Content-Type': 'application/json', 'Authorization': 'Bearer ' + token()})
    with urllib.request.urlopen(req, timeout=60) as r:
        res = json.load(r)
    if res.get('errors'):
        sys.exit('GraphQL error: ' + json.dumps(res['errors'], ensure_ascii=False)[:300])
    return res['data']


def confirm(what):
    if os.environ.get('ZEABUR_YES') == '1':
        return
    try:
        tty = open('/dev/tty')
    except OSError:
        sys.exit(f'{what}\n沒有終端機可以確認。請先取得使用者同意，再加上 ZEABUR_YES=1 執行。')
    with tty:
        print(f'{what}\n輸入 yes 繼續：', end='', flush=True)
        ans = tty.readline().strip()
    if ans != 'yes':
        sys.exit('cancelled')


def q(x):
    """GraphQL 字串字面值（JSON 跳脫）。"""
    return json.dumps(x)


def svc(sid, eid, fields):
    return gql('{ service(_id:%s){ %s(environmentID:%s){ %s } } }' % (q(sid), fields[0], q(eid), fields[1]))['service'][fields[0]]


def main(a):
    if len(a) < 3:
        sys.exit(__doc__)
    cmd, sid, eid = a[0], a[1], a[2]
    se = 'serviceID:%s, environmentID:%s' % (q(sid), q(eid))
    if cmd == 'keys':
        print('\n'.join(sorted(v['key'] for v in svc(sid, eid, ('variables', 'key')))))
    elif cmd == 'domains':
        for x in svc(sid, eid, ('domains', 'domain redirectTo status')):
            print(x['domain'], '->', x.get('redirectTo') or '-', x.get('status'))
    elif cmd == 'autorestart':
        print(svc(sid, eid, ('autoRestart', 'enabled restartHour')), '(restartHour is UTC)')
    elif cmd == 'set':
        k = a[3]
        v = sys.stdin.readline().rstrip('\n')
        if not v:
            sys.exit('empty value on stdin')
        confirm(f'set {k} on service {sid}')
        keys = {x['key'] for x in svc(sid, eid, ('variables', 'key'))}
        if k in keys:
            gql('mutation { updateSingleEnvironmentVariable(%s, oldKey:%s, newKey:%s, value:%s) { key } }' % (se, q(k), q(k), q(v)))
        else:
            gql('mutation { createEnvironmentVariable(%s, key:%s, value:%s) { key } }' % (se, q(k), q(v)))
        print('set', k, 'ok (restart the service to apply)')
    elif cmd == 'unset':
        k = a[3]
        confirm(f'delete {k} on service {sid}')
        gql('mutation { deleteSingleEnvironmentVariable(%s, key:%s) { key } }' % (se, q(k)))
        print('deleted', k)
    elif cmd == 'restart':
        confirm(f'restart service {sid}')
        gql('mutation { restartService(%s) }' % se)
        print('restart requested')
    elif cmd in ('redirect', 'unredirect'):
        sub = a[3]
        target = a[4] if cmd == 'redirect' else None
        confirm(f'{cmd} {sub}.zeabur.app' + (f' -> {target}' if target else '') + '（約 20 秒中斷）')
        gql('mutation { removeDomain(domain:%s) }' % q(sub + '.zeabur.app'))
        extra = ', redirectTo:%s' % q(target) if target else ''
        plain = 'mutation { addDomain(%s, domain:%s, isGenerated:true) { domain redirectTo status } }' % (se, q(sub))
        try:
            d = gql('mutation { addDomain(%s, domain:%s, isGenerated:true%s) { domain redirectTo status } }' % (se, q(sub), extra))
        except SystemExit as e:
            print('addDomain failed:', e, file=sys.stderr)
            if target:
                print('restoring the plain domain without redirect...', file=sys.stderr)
                gql(plain)
                print('restored', sub + '.zeabur.app (no redirect)', file=sys.stderr)
            else:
                print('manual fix: zeabur.py unredirect', sid, eid, sub, file=sys.stderr)
            sys.exit(1)
        print(d['addDomain'])
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main(sys.argv[1:])
