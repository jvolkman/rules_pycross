import asyncio

from grpclib.client import Channel


async def main():
    print("hello")
    async with Channel("127.0.0.1", 50051):
        pass


if __name__ == "__main__":
    asyncio.run(main())
