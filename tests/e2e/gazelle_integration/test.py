import requests
from dateutil import parser


def main():
    r = requests.get("https://google.com")
    print(r.status_code)

    d = parser.parse("2023-01-01T00:00:00Z")
    print(d)


if __name__ == "__main__":
    main()
