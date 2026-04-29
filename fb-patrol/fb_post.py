#!/usr/bin/env python3
"""
Facebook 粉專發文工具 (v2.0)
支援: 純文字發文, 圖片發文, 查詢最近貼文
用法:
  python3 fb_post.py "貼文內容"
  python3 fb_post.py "貼文內容" --link "https://..."
  python3 fb_post.py --history 5
"""

import requests
import sys
import os
import argparse
import json
from datetime import datetime, timezone, timedelta

# ===== 設定區 =====
PAGE_ID = os.environ.get("FB_PAGE_ID", "YOUR_PAGE_ID_HERE")
APP_ID = os.environ.get("FB_APP_ID", "YOUR_APP_ID_HERE")
# Token from original script
ACCESS_TOKEN = os.environ.get("FB_ACCESS_TOKEN", "YOUR_TOKEN_HERE")
API_VERSION = "v21.0"
# ==================

def convert_to_taipei(utc_str):
    """Convert UTC ISO string to Taipei Time (UTC+8)"""
    try:
        # Expected format: 2026-02-21T01:09:00+0000
        dt_utc = datetime.strptime(utc_str, "%Y-%m-%dT%H:%M:%S%z")
        dt_taipei = dt_utc.astimezone(timezone(timedelta(hours=8)))
        return dt_taipei.strftime("%Y-%m-%d %H:%M")
    except Exception:
        return utc_str[:16].replace('T', ' ')

def get_recent_posts(limit: int = 5):
    """取得最近的貼文"""
    url = f"https://graph.facebook.com/{API_VERSION}/{PAGE_ID}/feed"
    params = {
        "fields": "message,created_time,id,permalink_url",
        "limit": limit,
        "access_token": ACCESS_TOKEN
    }
    try:
        response = requests.get(url, params=params)
        response.raise_for_status()
        data = response.json().get('data', [])
        
        print(f"\n📊 最近 {len(data)} 則貼文:")
        for post in data:
            created_utc = post.get('created_time', '')
            created_taipei = convert_to_taipei(created_utc)
            msg = post.get('message', '').replace('\n', ' ')[:60]
            link = post.get('permalink_url', '')
            print(f"- [{created_taipei}] {msg}...")
            # print(f"  Link: {link}")
        return data
    except Exception as e:
        print(f"❌ 無法取得貼文歷史: {e}")
        return []

def post_to_facebook(message: str, link: str = None, photo_url: str = None, image_path: str = None):
    """發貼文到 Facebook 粉專"""
    base_url = f"https://graph.facebook.com/{API_VERSION}/{PAGE_ID}"
    
    # 決定 endpoint
    if image_path:
        url = f"{base_url}/photos"
        data = {"caption": message, "access_token": ACCESS_TOKEN}
        try:
            with open(image_path, "rb") as f:
                files = {"source": f}
                response = requests.post(url, data=data, files=files)
        except Exception as e:
            print(f"❌ 讀取圖片失敗: {e}")
            return
    elif photo_url:
        url = f"{base_url}/photos"
        data = {
            "url": photo_url,
            "caption": message,
            "access_token": ACCESS_TOKEN
        }
        response = requests.post(url, data=data)
    else:
        url = f"{base_url}/feed"
        data = {
            "message": message,
            "access_token": ACCESS_TOKEN
        }
        if link:
            data["link"] = link
        response = requests.post(url, data=data)
    
    try:
        result = response.json()
        if "error" in result:
            print(f"❌ 發文失敗: {result['error']['message']}")
        else:
            post_id = result.get("id") or result.get("post_id")
            print(f"✅ 發文成功!")
            print(f"   貼文 ID: {post_id}")
            print(f"   連結: https://www.facebook.com/{post_id}")
    except Exception as e:
        print(f"❌ 解析回應失敗: {e}")
        print(response.text)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Facebook Page Poster")
    
    # 互斥群組：要麼發文 (message)，要麼查詢歷史 (--history)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("message", nargs="?", help="Post content")
    group.add_argument("--history", type=int, metavar="N", help="Show last N posts")
    
    parser.add_argument("--link", help="Link to share")
    parser.add_argument("--photo", help="Photo URL to upload")
    parser.add_argument("--file", help="Local photo path to upload")

    args = parser.parse_args()

    if args.history:
        get_recent_posts(args.history)
    elif args.message:
        print(f"📝 準備發文到粉專...")
        print(f"   內容: {args.message[:50]}...")
        post_to_facebook(args.message, args.link, args.photo, args.file)
    else:
        parser.print_help()
