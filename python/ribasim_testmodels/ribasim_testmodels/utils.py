def offset_spatial_inplace(model, offset: tuple[float, float]):
    """Translate the geometry of a model with the given offset."""
    network = model.network
    network.edge.df.geometry = network.edge.df.geometry.translate(*offset)
    network.node.df.geometry = network.node.df.geometry.translate(*offset)
    return
