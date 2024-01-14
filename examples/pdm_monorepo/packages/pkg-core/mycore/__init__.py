def greet(name: str) -> str:
    return f"Hello {name}!"


def fib(n: int) -> int:
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)
