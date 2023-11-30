""" Assume that topic hei exists and is empty, then produce message and consume it"""
import os
import requests

def pretty_print(req):
    print('{}\n{}\r\n{}\r\n\r\n{}'.format(
        '-----------START-----------',
        req.method + ' ' + req.url,
        '\r\n'.join('{}: {}'.format(k, v) for k, v in req.headers.items()),
        req.body,
    ))

url = os.environ.get("REDPANDA_API_URL", "http://0.0.0.0:8082")
msg = {"records": [{"key": "thiskey", "value": "thisval", "partition": 0}]}
content_type = "application/vnd.kafka.json.v2+json"

print("Producing message to topic hei")
res = requests.post(url + "/topics/hei", json=msg, headers={"Content-Type": content_type})
pretty_print(res.request)
print("Produced message:", res.text)
res.raise_for_status()
assert res.json()["offsets"][0]["offset"] != -1, f"Failed to produce message, got: {res.text}"

print("Read messages from topic hei")
res = requests.get(
    url + "/topics/hei/partitions/0/records",
    headers={"Accept": content_type},
    params={"offset": 0, "max_bytes": 1048576, "timeout": 10},
)
pretty_print(res.request)
print("Read messages:", res.text)
res.raise_for_status()
