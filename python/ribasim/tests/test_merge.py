from datetime import datetime

from ribasim import Model
from ribasim.merge import _merge_models
from ribasim_testmodels import basic_model, tabulated_rating_curve_model


def test_merge_models(tmp_path):
    components = [basic_model(), tabulated_rating_curve_model()]
    model = Model(
        starttime=datetime(2020, 1, 1),
        endtime=datetime(2021, 1, 1),
        crs="EPSG:28992",
    )
    model = _merge_models(components, model, id_offset=1000, x_offset=100.0)

    n_nodes = [len(c.node.df) for c in components]
    assert len(model.node.df) == sum(n_nodes)
    assert len(model.link.df) == sum(len(c.link.df) for c in components)
    assert model.node.df.index.is_unique
    assert (model.node.df.index[n_nodes[0] :] >= 1000).all()
    assert (model.link.df.from_node_id.isin(model.node.df.index)).all()
    assert (model.link.df.to_node_id.isin(model.node.df.index)).all()
    assert model.basin.static.df.node_id.isin(model.node.df.index).all()
    # The second component is translated
    shifted = components[1].node.df.geometry.x.to_numpy() + 100.0
    assert (model.node.df.geometry.x.to_numpy()[n_nodes[0] :] == shifted).all()

    model.write(tmp_path / "merged/ribasim.toml")
    Model.read(tmp_path / "merged/ribasim.toml")
