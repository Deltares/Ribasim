def test_repr(basic):
    representation = repr(basic).split("\n")
    assert representation[0] == "<ribasim.Model>"
