#!/usr/bin/env python3
import os
import sys

print('Content-Type: text/plain')
print()
print('Hello from CGI!')
print(f'Method: {os.environ.get('REQUEST_METHOD', '')}')
print(f'Path: {os.environ.get('PATH_INFO', '')}')
print(f'Query: {os.environ.get('QUERY_STRING', '')}')
if os.environ.get('CONTENT_LENGTH', '0') != '0':
    print(f'Body: {sys.stdin.read()}')
