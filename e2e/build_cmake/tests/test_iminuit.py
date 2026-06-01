import iminuit


def test_iminuit():
    # Basic check that the C++ extension loads and works
    def f(x, y, z):
        return (x - 1) ** 2 + (y - 2) ** 2 + (z - 3) ** 2

    m = iminuit.Minuit(f, x=0, y=0, z=0)
    m.migrad()

    assert abs(m.values["x"] - 1.0) < 1e-3
    assert abs(m.values["y"] - 2.0) < 1e-3
    assert abs(m.values["z"] - 3.0) < 1e-3


if __name__ == "__main__":
    test_iminuit()
