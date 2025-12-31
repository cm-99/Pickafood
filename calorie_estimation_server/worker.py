import os
from redis import Redis
from rq import SpawnWorker, Queue, SimpleWorker

QUEUES = os.getenv("RQ_QUEUES", "gpu,cpu").split(",")
REDIS_URL = os.getenv("REDIS_URL", "redis://127.0.0.1:6379/0")

def main():
    conn = Redis.from_url(REDIS_URL)
    qs = [Queue(name, connection=conn) for name in QUEUES]
    SimpleWorker(qs, connection=conn).work(with_scheduler=True)

if __name__ == "__main__":
    main()