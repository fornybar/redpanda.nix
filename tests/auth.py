""" Test redpanda with security enabled """
import os
import requests
import aiokafka
import asyncio

def pretty_print(req):
    print('{}\n{}\r\n{}\r\n\r\n{}'.format(
        '-----------START-----------',
        req.method + ' ' + req.url,
        '\r\n'.join('{}: {}'.format(k, v) for k, v in req.headers.items()),
        req.body,
    ))

panda_url = os.environ.get("REDPANDA_PANDAPROXY_URL", "http://0.0.0.0:8082")
schema_url = os.environ.get("REDPANDA_SCHEMA_REGISTRY_URL", "http://0.0.0.0:8081")
kafka_server = os.environ.get("REDPANDA_KAFKA_SERVER", "0.0.0.0:9092")

msg = "{} -> Expected {}, got: {}"

print("Check pandaproxy unauthorized")
res = requests.get(panda_url + "/topics")
assert res.status_code == 401, msg.format(panda_url, 401, res.status_code)

print("Check schema registry unauthorized")
res = requests.get(schema_url + "/config")
assert res.status_code == 401, msg.format(schema_url, 401, res.status_code)

print("Check pandaproxy authorized")
res = requests.get(panda_url + "/topics", auth = ("admin", "admin"))
assert res.status_code == 200, msg.format(panda_url, 200, res.status_code)

print("Check schema registry authorized")
res = requests.get(schema_url + "/config", auth = ("admin", "admin"))
assert res.status_code == 200, msg.format(schema_url, 200, res.status_code)

KAFKA_SETTINGS = {
    "bootstrap_servers": kafka_server,
    "sasl_mechanism": "SCRAM-SHA-256",
    "sasl_plain_username": "admin",
    "sasl_plain_password": "admin",
    "security_protocol": "SASL_PLAINTEXT",
}

async def produce(settings):
    print("Start produce")
    producer = aiokafka.AIOKafkaProducer(**settings)
    await producer.start()
    print("Send message")
    await producer.send_and_wait("hei", b"padeg")
    await producer.stop()

async def consume(settings):
    print("Start consume")
    consumer = aiokafka.AIOKafkaConsumer("hei", auto_offset_reset= "earliest", **settings)
    await consumer.start()
    data = await consumer.getone()
    print("Consumed data: {}", data)
    await consumer.stop()


asyncio.run(produce(KAFKA_SETTINGS))
asyncio.run(consume(KAFKA_SETTINGS))


async def check_unauthorized(settings):
    res = await asyncio.gather(produce(settings), consume(settings), return_exceptions=True)
    print("Unauthorized produce and consume: {}", res)
    assert isinstance(res[0], aiokafka.errors.KafkaError), msg.format("produce", "KafkaError", res[0])
    assert isinstance(res[1], aiokafka.errors.KafkaError), msg.format("consume", "KafkaError", res[1])

asyncio.run(check_unauthorized({"bootstrap_servers": kafka_server}))
