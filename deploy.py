#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
热血玛法 1.76 —— 一键部署准备脚本
--------------------------------
作用：把手工操作降到 0。
  1) 自动生成版本号（时间戳），写入 sw.js 的 CACHE_VERSION
  2) 校验所有必需文件是否齐全
  3) 语法自检（HTML 里的 JS 片段是否可解析，需 node）
  4) 可选：直接打包成 zip

用法：
    python3 deploy.py              # 生成版本 + 校验
    python3 deploy.py --zip        # 生成版本 + 校验 + 打包
    python3 deploy.py --check      # 只校验，不改版本号（用于 CI）

做完后直接把 chuanqi-pwa/ 里的文件上传到托管平台即可，
用户下次打开会自动收到「发现新版本」提示。
"""
import os, re, sys, json, time, shutil, subprocess, tempfile

BASE = os.path.dirname(os.path.abspath(__file__))
REQUIRED = [
    'index.html', 'manifest.json', 'sw.js',
    'icons/icon-48.png', 'icons/icon-72.png', 'icons/icon-96.png',
    'icons/icon-144.png', 'icons/icon-152.png', 'icons/icon-180.png',
    'icons/icon-192.png', 'icons/icon-512.png',
]

def log(icon, msg):
    print('%s %s' % (icon, msg))

def gen_version():
    """时间戳版本号：可读 + 单调递增，如 malfa-20261001-145530"""
    return 'malfa-' + time.strftime('%Y%m%d-%H%M%S')

def check_files():
    missing = [f for f in REQUIRED if not os.path.exists(os.path.join(BASE, f))]
    if missing:
        log('✘', '缺少文件：' + '、'.join(missing))
        return False
    log('✔', '文件齐全（%d 项）' % len(REQUIRED))
    return True

def check_manifest():
    try:
        m = json.load(open(os.path.join(BASE, 'manifest.json'), encoding='utf-8'))
    except Exception as e:
        log('✘', 'manifest.json 解析失败：%s' % e)
        return False
    need = ['name', 'short_name', 'start_url', 'display', 'icons']
    miss = [k for k in need if k not in m]
    if miss:
        log('✘', 'manifest 缺少字段：' + '、'.join(miss))
        return False
    # 校验图标文件真实存在
    bad = [i['src'] for i in m.get('icons', [])
           if not os.path.exists(os.path.join(BASE, i['src']))]
    if bad:
        log('✘', 'manifest 引用了不存在的图标：' + '、'.join(bad))
        return False
    log('✔', 'manifest 合法（%d 个图标声明）' % len(m.get('icons', [])))
    return True

def check_html_js():
    """抽出 index.html 里的 <script> 内容做语法检查"""
    src = open(os.path.join(BASE, 'index.html'), encoding='utf-8').read()
    blocks = re.findall(r'<script>(.*?)</script>', src, re.S)
    if not blocks:
        log('✘', 'index.html 中未找到 <script> 块')
        return False
    code = '\n'.join(blocks)
    if shutil.which('node') is None:
        log('·', 'node 不可用，跳过语法检查')
        return True
    with tempfile.NamedTemporaryFile('w', suffix='.js', delete=False, encoding='utf-8') as f:
        f.write(code)
        tmp = f.name
    try:
        p = subprocess.run(['node', '--check', tmp], capture_output=True, text=True)
        if p.returncode != 0:
            log('✘', 'index.html 内 JS 语法错误：\n' + (p.stderr or '')[:400])
            return False
        log('✔', 'index.html 内 JS 语法通过（%d 个 script 块）' % len(blocks))
    finally:
        os.unlink(tmp)

    # sw.js 单独检查
    swp = os.path.join(BASE, 'sw.js')
    p2 = subprocess.run(['node', '--check', swp], capture_output=True, text=True)
    if p2.returncode != 0:
        log('✘', 'sw.js 语法错误：\n' + (p2.stderr or '')[:400])
        return False
    log('✔', 'sw.js 语法通过')
    return True

def bump_version(check_only=False):
    p = os.path.join(BASE, 'sw.js')
    src = open(p, encoding='utf-8').read()
    old = re.search(r"const CACHE_VERSION = '([^']*)'", src)
    old_v = old.group(1) if old else '(未知)'
    if check_only:
        log('·', 'sw.js 当前版本：%s（--check 模式，不修改）' % old_v)
        return old_v
    new_v = gen_version()
    src = re.sub(r"const CACHE_VERSION = '[^']*'",
                 "const CACHE_VERSION = '%s'" % new_v, src)
    open(p, 'w', encoding='utf-8').write(src)
    log('✔', 'sw.js 版本号：%s → %s' % (old_v, new_v))
    return new_v

def make_zip(version):
    name = '热血玛法-PWA版.zip'
    out = os.path.join(os.path.dirname(BASE), name)
    if os.path.exists(out):
        os.remove(out)
    files = ['index.html', 'manifest.json', 'sw.js', 'deploy.py', '部署说明.md'] + REQUIRED[3:]
    files = [f for f in files if os.path.exists(os.path.join(BASE, f))]
    with_zip = True
    try:
        import zipfile
        with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
            for f in files:
                z.write(os.path.join(BASE, f), f)
    except Exception as e:
        log('✘', '打包失败：%s' % e)
        return False
    size = os.path.getsize(out) / 1024.0
    log('✔', '已打包 %s（%.0f KB，%d 个文件）' % (name, size, len(files)))
    return True

def main():
    check_only = '--check' in sys.argv
    do_zip = '--zip' in sys.argv

    print('=' * 56)
    print('热血玛法 PWA 部署准备' + ('（仅校验）' if check_only else ''))
    print('=' * 56)

    allok = True
    allok &= check_files()
    allok &= check_manifest()
    allok &= check_html_js()
    ver = bump_version(check_only)
    allok = bool(allok)

    if do_zip and not check_only:
        allok &= make_zip(ver)

    print()
    if allok:
        print('✅ 准备完成，可以上传部署了')
        if not check_only:
            print('   当前版本：%s' % ver)
            print('   上传后，用户下次打开会在底部看到「发现新版本」提示条')
    else:
        print('❌ 存在问题，请先修复上面的错误')
        sys.exit(1)

if __name__ == '__main__':
    main()
