def test(basic):
    representation = repr(basic).split("\n")
    assert representation[0] == "<ribasim.Model>"
