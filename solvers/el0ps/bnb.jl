abstract type AbstractOptions end
abstract type AbstractResult end
abstract type AbstractSolver end

@enum SolverStatus begin
    OPTIMIZE_NOT_CALLED
    OPTIMAL
    TIME_LIMIT
    ITERATION_LIMIT
end

@enum ExplorationStrategy begin
    BFS
    DFS
end

@enum BranchingStrategy begin
    LARGEST
    RESIDUAL
end

Base.@kwdef struct BnbOptions <: AbstractOptions
    lb_solver::AbstractSolver           = CoordinateDescent(tolgap=1e-4, maxiter=10_000)
    ub_solver::AbstractSolver           = CoordinateDescent(tolgap=1e-8, maxiter=10_000)
    exploration::ExplorationStrategy    = DFS
    branching::BranchingStrategy        = LARGEST
    maxtime::Float64                    = 60.
    maxnode::Int                        = typemax(Int)
    tolgap::Float64                     = 0.
    tolint::Float64                     = 0.
    tolprune::Float64                   = 0.
    dualpruning::Bool                   = false
    l0screening::Bool                   = false
    l1screening::Bool                   = false
    verbosity::Bool                     = false
    showevery::Int                      = 1
    keeptrace::Bool                     = true
end

mutable struct BnbNode
    parent::Union{BnbNode,Nothing}
    S0::BitArray
    S1::BitArray
    Sb::BitArray
    lb::Float64
    ub::Float64
    x::Vector{Float64}
    w::Vector{Float64}
    u::Vector{Float64}
    x_ub::Vector{Float64}
    u_ub::Vector{Float64}
    function BnbNode(problem::Problem)
        return new(
            nothing,
            falses(problem.n),
            falses(problem.n),
            trues(problem.n),
            -Inf,
            Inf,
            zeros(problem.n),
            zeros(problem.m),
            -gradient(problem.F, problem.y, zeros(problem.m)),
            zeros(problem.n),
            zeros(problem.m),
        )
    end
    function BnbNode(parent::BnbNode, j::Int, jval::Int, prob::Problem)
        child = new(
            parent,
            copy(parent.S0),
            copy(parent.S1),
            copy(parent.Sb),
            copy(parent.lb),
            copy(parent.ub),
            copy(parent.x),
            copy(parent.w),
            copy(parent.u),
            copy(parent.x_ub),
            copy(parent.u_ub),
        )
        fixto!(child, j, jval, prob)
        return child
    end
end

abstract type AbstractSolver end
abstract type AbstractResult end
abstract type AbstractOptions end

Base.@kwdef mutable struct BnbTrace 
    ub::Vector{Float64}             = Vector{Float64}()
    lb::Vector{Float64}             = Vector{Float64}()
    node_count::Vector{Int}         = Vector{Int}()
    queue_size::Vector{Int}         = Vector{Int}()
    timer::Vector{Float64}          = Vector{Float64}()
    supp_pruned::Vector{Float64}    = Vector{Float64}()
    node_lb::Vector{Float64}        = Vector{Float64}()
    node_ub::Vector{Float64}        = Vector{Float64}()
    card_Sb::Vector{Int}            = Vector{Int}()
    card_S1::Vector{Int}            = Vector{Int}()
    card_S0::Vector{Int}            = Vector{Int}()
end

mutable struct BnbSolver <: AbstractSolver
    status::SolverStatus
    ub::Float64
    lb::Float64
    x::Vector{Float64}
    queue::Vector{BnbNode}
    node_count::Int
    supp_pruned::Float64
    start_time::Float64
    options::BnbOptions
    trace::BnbTrace
    function BnbSolver(; kwargs...)
        return new(
            OPTIMIZE_NOT_CALLED,
            Inf,
            -Inf,
            zeros(0),
            Vector{BnbNode}(),
            0,
            0.,
            Dates.time(),
            BnbOptions(; kwargs...),
            BnbTrace(),
        )
    end
end

struct BnbResult <: AbstractResult
    termination_status::SolverStatus
    solve_time::Float64
    node_count::Int
    objective_value::Float64
    relative_gap::Float64
    x::Vector{Float64}
    trace::BnbTrace
    function BnbResult(solver::BnbSolver, trace::BnbTrace)
        return new(
            solver.status,
            elapsed_time(solver),
            solver.node_count,
            solver.ub,
            gap(solver),
            solver.x,
            trace,
        )
    end
end

Base.show(io::IO, solver::BnbSolver) = print(io, "Bnb solver")

function Base.print(io::IO, result::BnbResult)
    println(io, "Bnb result")
    println(io, "  Status     : $(result.termination_status)")
    println(io, "  Objective  : $(result.objective_value)")
    println(io, "  Non-zeros  : $(norm(result.x, 0))")
    println(io, "  Last gap   : $(result.relative_gap)")
    println(io, "  Solve time : $(result.solve_time) seconds")
    print(io, "  Node count : $(result.node_count)")
end

function initialize!(solver::BnbSolver, problem::Problem, x0::Vector{Float64})
    solver.status = OPTIMIZE_NOT_CALLED
    solver.ub = objective(problem, x0)
    solver.lb = -Inf
    solver.x = x0
    push!(solver.queue, BnbNode(problem))
    solver.node_count = 0
    solver.supp_pruned = 0.
    solver.start_time = Dates.time()
    solver.trace = BnbTrace()
    return nothing
end

function header()
    str = (
        "  Nodes" *
        "   Time" * 
        "   Lower" *
        "   Upper" *
        " Rel gap" *
        " Abs gap" *
        "  %S0" *
        "  %S1" *
        "  %Sb"
    )
    return str
end

function display_head()
    str = header()
    println(repeat("-", length(str)))
    println(str)
    println(repeat("-", length(str)))
    return nothing
end

function display_trace(solver::BnbSolver, node)
    @printf "%7d" solver.node_count
    @printf " %6.2f" elapsed_time(solver)
    @printf " %7.2f" solver.lb
    @printf " %7.2f" solver.ub
    @printf "  %5.2f%%" 100 * gap(solver)
    @printf "   %.0e" abs(solver.ub - solver.lb)
    @printf " %3d%%" 100 * sum(node.S0) / length(node.S0)
    @printf " %3d%%" 100 * sum(node.S1) / length(node.S1)
    @printf " %3d%%" 100 * sum(node.Sb) / length(node.Sb)
    println()
end

function display_tail()
    str = header()
    println(repeat("-", length(str)))
end

depth(node::BnbNode) = sum(node.S0 .| node.S1)
elapsed_time(solver::BnbSolver) = Dates.time() - solver.start_time
gap(solver::BnbSolver) = abs(solver.ub - solver.lb) / abs(solver.ub + 1e-10)
is_terminated(solver::BnbSolver) = (solver.status != OPTIMIZE_NOT_CALLED)

function update_status!(solver::BnbSolver, options::BnbOptions)
    if elapsed_time(solver) >= options.maxtime
        solver.status = TIME_LIMIT
    elseif solver.node_count >= options.maxnode
        solver.status = ITERATION_LIMIT
    elseif gap(solver) <= options.tolgap
        solver.status = OPTIMAL
    elseif isempty(solver.queue)
        solver.status = OPTIMAL
    end
    return (solver.status != OPTIMIZE_NOT_CALLED)
end

function next_node!(solver::BnbSolver, options::BnbOptions)
    if options.exploration == DFS
        node = pop!(solver.queue)
        solver.node_count += 1
    elseif options.exploration == BFS
        node = popfirst!(solver.queue)
        solver.node_count += 1
    else
        error("Exploration strategy '$(options.exploration) not implemented yet")
    end
    return node
end

function prune!(solver::BnbSolver, node::BnbNode, options::BnbOptions)
    pruning_test = (node.lb > solver.ub + options.tolprune)
    perfect_test = (options.tolprune < abs(node.ub - node.lb) < options.tolgap) 
    prune = (pruning_test | perfect_test)
    if prune
        solver.supp_pruned += 2. ^ (-depth(node))
    end
    return prune
end

function branch!(prob::Problem, solver::BnbSolver, node::BnbNode, options::BnbOptions)
    !any(node.Sb) && return nothing
    if options.branching == LARGEST
        jSb = argmax(abs.(node.x[node.Sb]))
    elseif options.branching == RESIDUAL
        jSb = argmax(abs.(prob.A[:, node.Sb]' * node.u_ub))
    end
    j = (1:prob.n)[node.Sb][jSb]
    node_j0 = BnbNode(node, j, 0, prob)
    node_j1 = BnbNode(node, j, 1, prob)
    push!(solver.queue, node_j0)
    push!(solver.queue, node_j1)
    return nothing
end

function fixto!(node::BnbNode, j::Int, jval::Int, prob::Problem)
    node.Sb[j] || error("Branching index $j is already fixed")
    node.Sb[j] = false
    if jval == 0
        node.S0[j] = true
        if node.x[j] != 0.0
            axpy!(-node.x[j], prob.A[:, j], node.w)
            copy!(node.u, -gradient(prob.F, prob.y, node.w))
            node.x[j] = 0.0
        end
    elseif jval == 1
        node.S1[j] = true
    end
    return nothing
end

function update_bounds!(solver::BnbSolver, node::BnbNode, options::BnbOptions)
    if (node.ub ≈ solver.ub) & (norm(node.x_ub, 0) < norm(solver.x, 0))
        solver.ub = copy(node.ub)
        solver.x = copy(node.x_ub)
        filter!(queue_node -> !prune!(solver, queue_node, options), solver.queue)
        # filter!(queue_node -> queue_node.lb < solver.ub + options.tolprune, solver.queue)
    elseif node.ub < solver.ub
        solver.ub = copy(node.ub)
        solver.x = copy(node.x_ub)
        filter!(queue_node -> !prune!(solver, queue_node, options), solver.queue)
        # filter!(queue_node -> queue_node.lb < solver.ub + options.tolprune, solver.queue)
    end
    if isempty(solver.queue)
        solver.lb = min(node.lb, solver.ub)
    else
        solver.lb = minimum([queue_node.lb for queue_node in solver.queue])
    end
end

function update_trace!(trace::BnbTrace, solver::BnbSolver, node::BnbNode, options::BnbOptions)
    push!(trace.ub, solver.ub)
    push!(trace.lb, solver.lb)
    push!(trace.node_count, solver.node_count)
    push!(trace.queue_size, length(solver.queue))
    push!(trace.timer, elapsed_time(solver))
    push!(trace.supp_pruned, solver.supp_pruned)
    push!(trace.node_lb, node.lb)
    push!(trace.node_ub, node.ub)
    push!(trace.card_Sb, sum(node.Sb))
    push!(trace.card_S0, sum(node.S0))
    push!(trace.card_S1, sum(node.S1))
    return nothing
end

function optimize(
    solver::BnbSolver,
    problem::Problem;
    x0::Union{Vector{Float64},Nothing}=nothing,
    )

    x0 = isa(x0, Nothing) ? zeros(problem.n) : x0
    @assert length(x0) == problem.n
    initialize!(solver, problem, x0)

    options = solver.options
    trace = solver.trace

    options.verbosity && display_head()
    while true
        update_status!(solver, options) 
        is_terminated(solver) && break
        node = next_node!(solver, options)
        bound!(options.lb_solver, problem, solver, node, options, LOWER)
        if !(prune!(solver, node, options))
            bound!(options.ub_solver, problem, solver, node, options, UPPER)
            branch!(problem, solver, node, options)
        end
        update_bounds!(solver, node, options)
        options.keeptrace && update_trace!(trace, solver, node, options)
        options.verbosity && solver.node_count % options.showevery == 0 && display_trace(solver, node)
    end
    options.verbosity && display_tail()

    return BnbResult(solver, trace)

end