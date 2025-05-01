# lambda_function.py
import json
from flask import Flask, request
from werkzeug.serving import make_server

app = Flask(__name__)

@app.route('/', defaults={'path': ''}, methods=['GET', 'POST', 'PUT', 'DELETE', 'PATCH'])
@app.route('/<path:path>', methods=['GET', 'POST', 'PUT', 'DELETE', 'PATCH'])
def catch_all(path):
    with app.test_request_context(path=request.path, method=request.method, data=request.data, query_string=request.query_string):
        try:
            rv = app.full_dispatch_request()
        except Exception as e:
            # Log the exception
            print(f"Exception: {e}")
            raise
        response = make_response(rv)
        return response

def make_response(rv):
    status_code = 200
    headers = {}
    if isinstance(rv, tuple):
        rv, status_code, headers = rv + (headers,)[:3-len(rv)]
    elif isinstance(rv, str):
        rv = rv
    return {
        'statusCode': status_code,
        'body': rv,
        'headers': headers
    }


def handler(event, context):
    print("Event:", event)
    return catch_all(event['path'])