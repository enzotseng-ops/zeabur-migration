#!/usr/bin/env python3
"""
Facebook 粉絲團自動回覆工具 (v1.0)
邏輯:
  1. 取得粉絲專頁最近的貼文
  2. 檢查每一則貼文的留言
  3. 篩選出「尚未回覆」且「不是自己回覆」的留言
  4. 呼叫 LLM 生成回覆內容
  5. 發送回覆
"""

import requests
import os
import json
import time
from datetime import datetime

# ===== 設定區 =====
PAGE_ID = os.environ.get("FB_PAGE_ID", "YOUR_PAGE_ID_HERE")
ACCESS_TOKEN = os.environ.get("FB_ACCESS_TOKEN", "YOUR_TOKEN_HERE")
API_VERSION = "v21.0"
HISTORY_FILE = os.path.join(os.path.dirname(__file__), "fb_reply_history.json")
LOG_FILE = os.environ.get("FB_LOG_FILE", os.path.join(os.path.dirname(__file__), "fb_interactions_log.jsonl"))
QA_LIBRARY = os.environ.get("FB_QA_LIBRARY", os.path.join(os.path.dirname(__file__), "qa_library.md"))
MCP_ENDPOINT = "http://localhost:3025/mcp"
MCP_API_KEY = os.environ.get("MCP_API_KEY", "YOUR_MCP_KEY_HERE")

def get_posts():
    url = f"https://graph.facebook.com/{API_VERSION}/{PAGE_ID}/feed"
    params = {"access_token": ACCESS_TOKEN, "limit": 5}
    res = requests.get(url, params=params)
    return res.json().get('data', [])

def get_comments(post_id):
    url = f"https://graph.facebook.com/{API_VERSION}/{post_id}/comments"
    params = {"access_token": ACCESS_TOKEN, "fields": "id,message,from,created_time"}
    res = requests.get(url, params=params)
    return res.json().get('data', [])

def reply_to_comment(comment_id, message):
    url = f"https://graph.facebook.com/{API_VERSION}/{comment_id}/comments"
    data = {"message": message, "access_token": ACCESS_TOKEN}
    res = requests.post(url, data=data)
    return res.json()

def load_history():
    if os.path.exists(HISTORY_FILE):
        with open(HISTORY_FILE, 'r') as f:
            return json.load(f)
    return []

def save_history(history):
    with open(HISTORY_FILE, 'w') as f:
        json.dump(history, f)

def main():
    history = load_history()
    posts = get_posts()
    found_new = False
    
    for post in posts:
        post_id = post['id']
        comments = get_comments(post_id)
        
        for comment in comments:
            comment_id = comment['id']
            if comment_id in history:
                continue
            if comment.get('from', {}).get('id') == PAGE_ID:
                continue
                
            user_name = comment.get('from', {}).get('name', '網友')
            user_msg = comment.get('message', '')
            
            # 只有發現新留言時才輸出
            print(f"ACTION_REQUIRED:REPLY_TO:{comment_id}:USER:{user_name}:MSG:{user_msg}")
            found_new = True
    
    if not found_new:
        # 如果完全沒新訊息，直接輸出這個標記供外層判斷
        print("STATUS:NO_NEW_MESSAGES")

if __name__ == "__main__":
    main()
