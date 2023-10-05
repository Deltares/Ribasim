"""Whether the given node node is flow constraining by having a maximum flow rate."""
is_flow_constraining(node::AbstractParameterNode) = hasfield(typeof(node), :max_flow_rate)

"""Whether the given node is flow direction constraining (only in direction of edges)."""
is_flow_direction_constraining(node::AbstractParameterNode) =
    (nameof(typeof(node)) ∈ [:Pump, :Outlet, :TabulatedRatingCurve])

"""
Construct the graph used for the max flow problems for allocation in subnetworks.

Definitions
-----------
- 'subnetwork' is used to refer to the original Ribasim subnetwork;
- 'MFG' is used to refer to the max flow graph.

Inputs
------
p: Ribasim model parameters
subnetwork_node_ids: the model node IDs that are part of the allocation subnetwork
source_node_id: the model node ID of the source node (currently only flow boundary supported)

Outputs
-------
A Subnetwork object, see solve.jl

Notes
-----
- In the MFG, the source has ID 1 and the sink has ID 2;

"""
function get_graph_max_flow(
    p::Parameters,
    subnetwork_node_ids::Vector{Int},
    source_node_id::Int,
)::Subnetwork
    (; connectivity, user, lookup) = p
    (; graph_flow) = connectivity

    # Mapping node_id => MFG_node_id where such a correspondence exists
    node_id_mapping = Dict{Int, Int}()

    # MFG source:   MFG_id = 1
    # MFG sink:     MFG_id = 2
    n_MFG_nodes = 2
    node_id_mapping[source_node_id] = 1

    # Determine the number of nodes in the MFG
    for subnetwork_node_id in subnetwork_node_ids
        node_type = lookup[subnetwork_node_id]

        if node_type == :user
            # Each user in the subnetwork gets an MFG node
            n_MFG_nodes += 1
            node_id_mapping[subnetwork_node_id] = n_MFG_nodes

        elseif length(all_neighbors(graph_flow, subnetwork_node_id)) > 2
            # Each junction (that is, a node with more than 2 neighbors)
            # in the subnetwork gets an MFG node
            n_MFG_nodes += 1
            node_id_mapping[subnetwork_node_id] = n_MFG_nodes
        end
    end

    # The MFG and its edge capacities
    graph_max_flow = DiGraph(n_MFG_nodes)
    capacity = spzeros(n_MFG_nodes, n_MFG_nodes)

    # The ids of the subnetwork nodes that have an equivalent in the MFG
    subnetwork_node_ids_represented = keys(node_id_mapping)

    # This loop finds MFG edges in several ways:
    # - Between the users and the sink
    # - Between MFG nodes whose equivalent in the subnetwork are directly connected
    # - Between MFG nodes whose equivalent in the subnetwork are connected
    #   with one or more non-junction nodes in between
    MFG_edges_composite = Vector{Int}[]
    for subnetwork_node_id in subnetwork_node_ids
        subnetwork_neighbor_ids = all_neighbors(graph_flow, subnetwork_node_id)

        if subnetwork_node_id in subnetwork_node_ids_represented
            if subnetwork_node_id in user.node_id
                # Add edges in MFG graph from users to the sink
                MFG_node_id = node_id_mapping[subnetwork_node_id]
                add_edge!(graph_max_flow, MFG_node_id, 2)
                # Capacity depends on user demand at a given priority
                capacity[MFG_node_id, 2] = 0.0
            else
                # Direct connections in the subnetwork between nodes that
                # have an equivaent MFG graph node
                for subnetwork_neighbor_id in subnetwork_neighbor_ids
                    if subnetwork_neighbor_id in subnetwork_node_ids_represented &&
                       subnetwork_neighbor_id ≠ source_node_id
                        MFG_node_id_1 = node_id_mapping[subnetwork_node_id]
                        MFG_node_id_2 = node_id_mapping[subnetwork_neighbor_id]
                        add_edge!(graph_max_flow, MFG_node_id_1, MFG_node_id_2)
                        # These direct connections cannot have capacity constraints
                        capacity[MFG_node_id_1, MFG_node_id_2] = Inf
                    end
                end
            end
        else
            # Try to find an existing MFG composite edge to add the current subnetwork_node_id to
            found_edge = false
            for MFG_edge_composite in MFG_edges_composite
                if MFG_edge_composite[1] in subnetwork_neighbor_ids
                    pushfirst!(MFG_edge_composite, subnetwork_node_id)
                    found_edge = true
                    break
                elseif MFG_edge_composite[end] in subnetwork_neighbor_ids
                    push!(MFG_edge_composite, subnetwork_node_id)
                    found_edge = true
                    break
                end
            end

            # Start a new MFG composite edge if no existing edge to append to was found
            if !found_edge
                push!(MFG_edges_composite, [subnetwork_node_id])
            end
        end
    end

    # For the composite MFG edges:
    # - Find out whether they are connected to MFG nodes on both ends
    # - Compute their capacity
    # - Find out their allowed flow direction(s)
    for MFG_edge_composite in MFG_edges_composite
        # Find MFG node connected to this edge on the first end
        MFG_node_id_1 = nothing
        subnetwork_neighbors_side_1 = all_neighbors(graph_flow, MFG_edge_composite[1])
        for subnetwork_neighbor_node_id in subnetwork_neighbors_side_1
            if subnetwork_neighbor_node_id in subnetwork_node_ids_represented
                MFG_node_id_1 = node_id_mapping[subnetwork_neighbor_node_id]
                pushfirst!(MFG_edge_composite, subnetwork_neighbor_node_id)
                break
            end
        end

        # No connection to a max flow node found on this side, so edge is discarded
        if isnothing(MFG_node_id_1)
            continue
        end

        # Find MFG node connected to this edge on the second end
        MFG_node_id_2 = nothing
        subnetwork_neighbors_side_2 = all_neighbors(graph_flow, MFG_edge_composite[end])
        for subnetwork_neighbor_node_id in subnetwork_neighbors_side_2
            if subnetwork_neighbor_node_id in subnetwork_node_ids_represented
                MFG_node_id_2 = node_id_mapping[subnetwork_neighbor_node_id]
                # Make sure this MFG node is distinct from the other one
                if MFG_node_id_2 ≠ MFG_node_id_1
                    push!(MFG_edge_composite, subnetwork_neighbor_node_id)
                    break
                end
            end
        end

        # No connection to MFG node found on this side, so edge is discarded
        if isnothing(MFG_node_id_2)
            continue
        end

        # Find capacity of this composite MFG edge
        positive_flow = true
        negative_flow = true
        MFG_edge_capacity = Inf
        for (i, subnetwork_node_id) in enumerate(MFG_edge_composite)
            # The start and end subnetwork nodes of the composite MFG
            # edge are now nodes that have an equivalent in the MFG graph,
            # these do not constrain the composite edge capacity
            if i == 1 || i == length(MFG_edge_composite)
                continue
            end
            node_type = lookup[subnetwork_node_id]
            node = getfield(p, node_type)

            # Find flow constraints
            if is_flow_constraining(node)
                model_node_idx = Ribasim.findsorted(node.node_id, subnetwork_node_id)
                MFG_edge_capacity =
                    min(MFG_edge_capacity, node.max_flow_rate[model_node_idx])
            end

            # Find flow direction constraints
            if is_flow_direction_constraining(node)
                subnetwork_inneighbor_node_id =
                    only(inneighbors(graph_flow, subnetwork_node_id))

                if subnetwork_inneighbor_node_id == MFG_edge_composite[i - 1]
                    negative_flow = false
                elseif subnetwork_inneighbor_node_id == MFG_edge_composite[i + 1]
                    positive_flow = false
                end
            end
        end

        # Add composite MFG edge(s)
        if positive_flow
            add_edge!(graph_max_flow, MFG_node_id_1, MFG_node_id_2)
            capacity[MFG_node_id_1, MFG_node_id_2] = MFG_edge_capacity
        end

        if negative_flow
            add_edge!(graph_max_flow, MFG_node_id_2, MFG_node_id_1)
            capacity[MFG_node_id_2, MFG_node_id_1] = MFG_edge_capacity
        end
    end

    # Invert the node id mapping to easily translate from MFG nodes to subnetwork nodes
    node_id_mapping_inverse = Dict(values(node_id_mapping) .=> keys(node_id_mapping))

    return Subnetwork(
        subnetwork_node_ids,
        node_id_mapping,
        node_id_mapping_inverse,
        graph_max_flow,
        capacity,
        copy(capacity),
    )
end

"""
Loop over the priorities and allocate the demands, taking restrictions
in the allocation subnetwork into account by solving a max flow problem per priority.
When not enough water is left to allocate what the max flow problem prescribes, the residual
source flow capacity is distributed according to the provided residual_allocation_type,
see the allocate_residual! methods.
"""
function allocate!(
    user::Ribasim.User,
    subnetwork::Subnetwork,
    source_capacity::Float64,
    t::Float64;
    plot_folder::Union{String, Nothing} = nothing,
    gdf_node::Union{DataFrame, Nothing} = nothing,
    residual_allocation_type::Symbol = :proportional,
)::Nothing
    (; capacity, capacity_fixed, node_id_mapping, graph_max_flow) = subnetwork
    (; node_id, priority, demand, allocated) = user

    source_capacity_left = source_capacity

    # Set the maximum capacity of the edges in the max flow graph
    capacity .= capacity_fixed

    # Loop over available priorities
    for p in 1:maximum(priority)

        # Set user demands as capacities in the max flow graph
        # and collect the total demand for this priority
        demand_p_sum = 0.0
        for (i, model_node_id) in enumerate(node_id)
            if priority[i] == p
                demand_p = demand[i](t)
            else
                demand_p = 0.0
            end

            MFP_id = node_id_mapping[model_node_id]
            capacity[MFP_id, 2] = demand_p
            demand_p_sum += demand_p
        end

        # The max flow solver cannot deal with infinite capacities,
        # so the infinities are relpaced by the sum of the demands of this priority,
        # which is an upper bound for the flow trough the max flow graph so this is
        # never constraining.
        capacity[isinf.(capacity_fixed)] .= demand_p_sum

        # Solve the max flow problem
        total_flow_p, flows_p = maximum_flow(graph_max_flow, 1, 2, capacity)

        if !isnothing(plot_folder)
            fig, ax = plot_graph_max_flow(subnetwork; gdf_node, max_capacity = demand_p_sum)
            save(normpath("$plot_folder/Ribasim_max_flow_solution_p_$(p)_noflow.png"), fig)
            fig, ax = plot_graph_max_flow(
                subnetwork;
                flow = flows_p,
                gdf_node,
                max_capacity = demand_p_sum,
            )
            save(normpath("$plot_folder/Ribasim_max_flow_solution_p_$(p)_flow.png"), fig)
        end

        if total_flow_p > source_capacity_left
            # If the max flow problem allocates more flow to the users than there is source flow capacity left,
            # allocate the residual source flow capacity according to the provided residual_allocation_type
            # and end the allocation algorithm
            allocate_residual!(
                user,
                subnetwork,
                source_capacity_left,
                total_flow_p,
                p,
                flows_p,
                Val{residual_allocation_type}(),
            )
            break
        else
            for (i, model_node_id) in enumerate(node_id)
                if priority[i] == p
                    # Set the allocation of the users as the flow between
                    # the user node and the sink node in the MFG
                    MFP_node_id = node_id_mapping[model_node_id]
                    allocated[i] = flows_p[MFP_node_id, 2]
                end
            end
            # Subtract the source flow capacity used for this priority from the
            # total source capacity that is left
            source_capacity_left -= total_flow_p

            # Subtract the flows over the edges for this priority
            # from the edge capacities in the MFG
            capacity .-= flows_p
        end
    end

    return nothing
end

"""
Allocate the residual source flow capacity according to the 'proportional' strategy,
that is, each user gets the same proportion of the flow that was allocated to them
by the max flow algorithm such that the residual source flow is used up exactly.
This strategy maximises the minimal proportion each user gets of what was originally
allocation to them by the max flow algorithm.
"""
function allocate_residual!(
    user::Ribasim.User,
    subnetwork::Subnetwork,
    source_capacity_residual::Float64,
    allocated_total_priority_last::Float64,
    priority_last::Int,
    flows::AbstractMatrix,
    type::Val{:proportional},
)::Nothing
    (; node_id_mapping_inverse, graph_max_flow) = subnetwork
    (; node_id, priority, allocated) = user

    # The fraction each user gets of what was allocated to them by the max flow algorithm
    fraction = source_capacity_residual / allocated_total_priority_last

    # Allocate the fractions to the users
    for MFG_node_id in inneighbors(graph_max_flow, 2)
        subnetwork_node_id = node_id_mapping_inverse[MFG_node_id]
        subnetwork_node_idx = Ribasim.findsorted(node_id, subnetwork_node_id)
        if priority[subnetwork_node_idx] == priority_last
            allocated_originally = flows[MFG_node_id, 2]
            allocated[subnetwork_node_idx] = fraction * allocated_originally
        end
    end
    return nothing
end

"""
Plot max flow graphs, with or without the max flow result.
"""
function plot_graph_max_flow(
    subnetwork::Subnetwork;
    flow::Union{AbstractMatrix{Float64}, Nothing} = nothing,
    gdf_node::Union{DataFrame, Nothing} = nothing,
    max_capacity::Float64 = 5.0,
)
    (; graph_max_flow, capacity, node_id_mapping) = subnetwork
    node_ids = 1:nv(graph_max_flow)
    ilabels = string.(node_ids)

    # Edge widths and arrow sizes
    edge_capacity_with_inf = [capacity[e.src, e.dst] for e in edges(graph_max_flow)]
    edge_capacity = copy(edge_capacity_with_inf)
    replace!(edge_capacity, Inf => max_capacity)
    edge_width = edge_capacity * 10 / maximum(edge_capacity)
    edge_width = clamp.(edge_width, 3.0, 15.0)
    arrow_size = 4 * edge_width

    # Node colors
    node_color = fill(:gray80, nv(graph_max_flow))
    node_color[1] = :lightgreen
    node_color[2] = :tomato

    # Get node locations
    if all(.!isnothing.([node_id_mapping, gdf_node]))
        node_id_mapping_inverse = Dict(values(node_id_mapping) .=> keys(node_id_mapping))
        MFP_node_locations = Point[]
        for id in 1:nv(graph_max_flow)
            if id == 2
                point = Point(5.0, 5.0)
            else
                point = gdf_node.geom[node_id_mapping_inverse[id]]
                point = Point(coordinates(point)...)
            end
            push!(MFP_node_locations, point)
        end
    else
        MFP_node_locations = Spring()
    end

    # Edge labels (capacities and flows if available)
    elabels = if all(.!isnothing.([node_id_mapping, flow, gdf_node]))
        [
            string(flow[e.src, e.dst], " / ", capacity[e.src, e.dst]) for
            e in edges(graph_max_flow)
        ]
    else
        [string(capacity[e.src, e.dst]) for e in edges(graph_max_flow)]
    end

    fig = graphplot(
        graph_max_flow;
        layout = MFP_node_locations,
        ilabels,
        elabels,
        node_color,
        edge_color = :gray80,
        edge_width,
        arrow_size,
        arrow_shift = :end,
    )
    ax = current_axis()
    ax.aspect = AxisAspect(1)
    hidedecorations!(ax)
    hidespines!(ax)

    # PLot flows as blue edges
    if all(.!isnothing.([node_id_mapping, flow, gdf_node]))
        edge_flow = [flow[e.src, e.dst] for e in edges(graph_max_flow)]
        edge_width = edge_flow * 10 / maximum(edge_capacity)
        edge_width = clamp.(edge_width, 0.0, 15.0)
        graphplot!(
            graph_max_flow;
            layout = MFP_node_locations,
            ilabels,
            edge_width,
            node_color,
            edge_color = :blue,
            arrow_show = false,
        )
    end
    return fig, ax
end
