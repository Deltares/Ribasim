import geopandas as gpd
import pytest
import shapely.geometry as sg
from pydantic import ValidationError
from ribasim.geometry.link import LinkTable, NodeData


@pytest.fixture(scope="session")
def link() -> LinkTable:
    a = (0.0, 0.0)
    b = (0.0, 1.0)
    c = (0.2, 0.5)
    d = (1.0, 1.0)
    geometry = [sg.LineString([a, b, c]), sg.LineString([a, d])]
    df = gpd.GeoDataFrame(
        data={"link_id": [0, 1], "from_node_id": [1, 1], "to_node_id": [2, 3]},
        geometry=geometry,
    )
    df.set_index("link_id", inplace=True)
    link = LinkTable(df=df)
    return link


def test_validation(link):
    assert isinstance(link, LinkTable)

    with pytest.raises(ValidationError):
        df = gpd.GeoDataFrame(
            data={
                "link_id": [0, 1],
                "from_node_id": [1, 1],
                "to_node_id": ["foo", 3],
            },  # None is coerced to 0 without errors
            geometry=[None, None],
        )
        df.set_index("link_id", inplace=True)
        LinkTable(df=df)


def test_link_plot(link):
    link.plot()


def test_link_indexing(link):
    with pytest.raises(NotImplementedError):
        link[1]


def test_invalid_retour_link(basic):
    with pytest.raises(ValueError, match="opposite link already exists"):
        basic.link.add(basic.manning_resistance[2], basic.basin[1])


def test_node_data():
    node = NodeData(node_id=5, node_type="Pump", geometry=sg.Point(0, 0))
    assert repr(node) == "Pump #5"
