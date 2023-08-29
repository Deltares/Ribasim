import pytest
import ribasim
import ribasim_testmodels


@pytest.mark.parametrize(
    "model_constructor",
    map(ribasim_testmodels.__dict__.get, ribasim_testmodels.__all__),
)
def test_models(model_constructor):
    model = model_constructor()
    assert isinstance(model, ribasim.Model)
