using BlockArrays, SparseArrays, Setfield

# structure to describe a (Time) mesh using the time steps t_{i+1} - t_{i}. If the time steps are constant, we do not record them but, instead, we save the number of time steps
struct TimeMesh{T}
	ds::T
end

TimeMesh(M::Int64) = TimeMesh{Int64}(M)

@inline canAdapt(ms::TimeMesh{Ti}) where Ti = !(Ti == Int64)
Base.length(ms::TimeMesh{Ti}) where Ti = length(ms.ds)
Base.length(ms::TimeMesh{Ti}) where {Ti <: Int} = ms.ds

# access the time steps
@inline getTimeStep(ms, i::Int) = ms.ds[i]
@inline getTimeStep(ms::TimeMesh{Ti}, i::Int) where {Ti <: Int} = 1.0 / ms.ds

Base.collect(ms::TimeMesh) = ms.ds
Base.collect(ms::TimeMesh{Ti}) where {Ti <: Int} = repeat([getTimeStep(ms, 1)], ms.ds)
####################################################################################################
const DocStrjacobianPOTrap = """
- `jacobian = :FullLU`. Specify the choice of the jacobian (and linear algorithm), `jacobian` must belong to `[:FullLU, :FullSparseInplace, :BorderedLU, :FullMatrixFree, :BorderedMatrixFree, :FullSparseInplace]`. This is used to select a way of inverting the jacobian `dG` of the functional G.
- For `jacobian = :FullLU`, we use the default linear solver based on a sparse matrix representation of `dG`. This matrix is assembled at each newton iteration. This is the default algorithm.
- For `jacobian = :FullSparseInplace`, this is the same as for `:FullLU` but the sparse matrix `dG` is updated inplace. This method allocates much less. In some cases, this is significantly faster than using `:FullLU`. Note that this method can only be used if the sparsity pattern of the jacobian is always the same.
- For `jacobian = :Dense`, same as above but the matrix `dG` is dense. It is also updated inplace. This option is useful to study ODE of small dimension.
- For `jacobian = :DenseAD`, evaluate the jacobian using ForwardDiff
- For `jacobian = :BorderedLU`, we take advantage of the bordered shape of the linear solver and use a LU decomposition to invert `dG` using a bordered linear solver.
- For `jacobian = :BorderedSparseInplace`, this is the same as for `:BorderedLU` but the cyclic matrix `dG` is updated inplace. This method allocates much less. In some cases, this is significantly faster than using `:BorderedLU`. Note that this method can only be used if the sparsity pattern of the jacobian is always the same.
- For `jacobian = :FullMatrixFree`, a matrix free linear solver is used for `dG`: note that a preconditioner is very likely required here because of the cyclic shape of `dG` which affects negatively the convergence properties of GMRES.
- For `jacobian = :BorderedMatrixFree`, a matrix free linear solver is used but for `Jc` only (see docs): it means that `options.linsolver` is used to invert `Jc`. These two Matrix-Free options thus expose different part of the jacobian `dG` in order to use specific preconditioners. For example, an ILU preconditioner on `Jc` could remove the constraints in `dG` and lead to poor convergence. Of course, for these last two methods, a preconditioner is likely to be required.
- For `jacobian = :FullMatrixFreeAD`, the evalution map of the differential is derived using automatic differentiation. Thus, unlike the previous two cases, the user does not need to pass a Matrix-Free differential.
"""

# method using the Trapezoidal rule (Order 2 in time) and discretisation of the periodic orbit.
"""

This composite type implements Finite Differences based on a Trapezoidal rule (Order 2 in time) to locate periodic orbits. More details (maths, notations, linear systems) can be found [here](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/periodicOrbitTrapeze/).

## Arguments
- `prob` a bifurcation problem
- `M::Int` number of time slices
- `ϕ` used to set a section for the phase constraint equation, of size N*M
- `xπ` used in the section for the phase constraint equation, of size N*M
- `linsolver: = DefaultLS()` linear solver for each time slice, i.e. to solve `J⋅sol = rhs`. This is only needed for the computation of the Floquet multipliers in a full matrix-free setting.
- `ongpu::Bool` whether the computation takes place on the gpu (Experimental)
- `massmatrix` a mass matrix. You can pass for example a sparse matrix. Default: identity matrix.
- `updateSectionEveryStep` updates the section every `updateSectionEveryStep` step during continuation
- `jacobian::Symbol` symbol which describes the type of jacobian used in Newton iterations (see below).

The scheme is as follows. We first consider a partition of ``[0,1]`` given by ``0<s_0<\\cdots<s_m=1`` and one looks for `T = x[end]` such that

 ``M_a\\cdot\\left(x_{i} - x_{i-1}\\right) - \\frac{T\\cdot h_i}{2} \\left(F(x_{i}) + F(x_{i-1})\\right) = 0,\\ i=1,\\cdots,m-1``

with ``u_{0} := u_{m-1}`` and the periodicity condition ``u_{m} - u_{1} = 0`` and

where ``h_1 = s_i-s_{i-1}``. ``M_a`` is a mass matrix. Finally, the phase of the periodic orbit is constrained by using a section (but you could use your own)

 ``\\sum_i\\langle x_{i} - x_{\\pi,i}, \\phi_{i}\\rangle=0.``

# Orbit guess
You will see below that you can evaluate the residual of the functional (and other things) by calling `pb(orbitguess, p)` on an orbit guess `orbitguess`. Note that `orbitguess` must be a vector of size M * N + 1 where N is the number of unknowns in the state space and `orbitguess[M*N+1]` is an estimate of the period ``T`` of the limit cycle. More precisely, using the above notations, `orbitguess` must be ``orbitguess = [x_{1},x_{2},\\cdots,x_{M}, T]``.

Note that you can generate this guess from a function solution using `generateSolution`.

# Functional
 A functional, hereby called `G`, encodes this problem. The following methods are available

- `pb(orbitguess, p)` evaluates the functional G on `orbitguess`
- `pb(orbitguess, p, du)` evaluates the jacobian `dG(orbitguess).du` functional at `orbitguess` on `du`
- `pb(Val(:JacFullSparse), orbitguess, p)` return the sparse matrix of the jacobian `dG(orbitguess)` at `orbitguess` without the constraints. It is called `A_γ` in the docs.
- `pb(Val(:JacFullSparseInplace), J, orbitguess, p)`. Same as `pb(Val(:JacFullSparse), orbitguess, p)` but overwrites `J` inplace. Note that the sparsity pattern must be the same independantly of the values of the parameters or of `orbitguess`. In this case, this is significantly faster than `pb(Val(:JacFullSparse), orbitguess, p)`.
- `pb(Val(:JacCyclicSparse), orbitguess, p)` return the sparse cyclic matrix Jc (see the docs) of the jacobian `dG(orbitguess)` at `orbitguess`
- `pb(Val(:BlockDiagSparse), orbitguess, p)` return the diagonal of the sparse matrix of the jacobian `dG(orbitguess)` at `orbitguess`. This allows to design Jacobi preconditioner. Use `blockdiag`.

# Jacobian
$DocStrjacobianPOTrap

!!! note "GPU call"
    For these methods to work on the GPU, for example with `CuArrays` in mode `allowscalar(false)`, we face the issue that the function `extractPeriodFDTrap` won't be well defined because it is a scalar operation. Note that you must pass the option `ongpu = true` for the functional to be evaluated efficiently on the gpu.
"""
@with_kw_noshow struct PeriodicOrbitTrapProblem{Tprob, vectype, Tls <: AbstractLinearSolver, Tmesh, Tmass} <: AbstractPOFDProblem
	# porblem which contains the vector field F(x, par)
	prob_vf::Tprob = nothing

	# variables to define a Section for the phase constraint equation
	ϕ::vectype = nothing
	xπ::vectype = nothing

	# discretisation of the time interval
	M::Int = 0
	mesh::Tmesh = TimeMesh(M)

	# dimension of the problem in case of an AbstractVector
	N::Int = 0

	# linear solver for each slice, i.e. to solve J⋅sol = rhs. This is mainly used for the computation of the Floquet coefficients
	linsolver::Tls = DefaultLS()

	# whether the computation takes place on the gpu
	ongpu::Bool = false

	# whether the problem is nonautonomous
	isautonomous::Bool = true

	# mass matrix
	massmatrix::Tmass = nothing

	updateSectionEveryStep::Int = 1
	jacobian::Symbol = :Dense
end

function Base.show(io::IO, pb::PeriodicOrbitTrapProblem)
	println(io, "┌─ Trapezoid functional for periodic orbits")
	println(io, "├─ time slices    : ", pb.M)
	println(io, "├─ dimension      : ", pb.N)
	println(io, "├─ jacobian       : ", pb.jacobian)
	println(io, "├─ update section : ", pb.updateSectionEveryStep)
	println(io, "└─ inplace        : ", isInplace(pb))
end

@inline isInplace(pb::PeriodicOrbitTrapProblem) = isnothing(pb.prob_vf) ? false : isInplace(pb.prob_vf)
@inline getTimeStep(pb::AbstractPOFDProblem, i::Int) = getTimeStep(pb.mesh, i)
getTimes(pb::AbstractPOFDProblem) = cumsum(collect(pb.mesh))
@inline hasmassmatrix(pb::PeriodicOrbitTrapProblem) = ~isnothing(pb.massmatrix)
@inline getParams(pb::PeriodicOrbitTrapProblem) = getParams(pb.prob_vf)
@inline getLens(pb::PeriodicOrbitTrapProblem) = getLens(pb.prob_vf)
@inline function getMassMatrix(pb::PeriodicOrbitTrapProblem, returnArray = false)
	if returnArray == false
		return hasmassmatrix(pb) ? pb.massmatrix : spdiagm( 0 => ones(pb.N))
	else
		return hasmassmatrix(pb) ? pb.massmatrix : LinearAlgebra.I(pb.N)
	end
end

# for a dummy constructor, useful for specifying the "algorithm" to look for periodic orbits,
# just call PeriodicOrbitTrapProblem()

function PeriodicOrbitTrapProblem(prob, ϕ::vectype, xπ::vectype, m::Union{Int, vecmesh}, ls::AbstractLinearSolver = DefaultLS(); ongpu = false, massmatrix = nothing) where {vectype, vecmesh <: AbstractVector}
	_length = ϕ isa AbstractVector ? length(ϕ) : 0
	M = m isa Number ? m : length(m) + 1

	return PeriodicOrbitTrapProblem(prob_vf = prob, ϕ = ϕ, xπ = xπ, M = M, mesh = TimeMesh(m), N = _length ÷ M, linsolver = ls, ongpu = ongpu, massmatrix = massmatrix)
end

# PeriodicOrbitTrapProblem(F, J, ϕ::vectype, xπ::vectype, m::Union{Int, vecmesh}, ls::AbstractLinearSolver = DefaultLS(); isinplace = false, ongpu = false, adaptmesh = false, massmatrix = nothing) where {vectype, vecmesh <: AbstractVector} = PeriodicOrbitTrapProblem(F, J, nothing, ϕ, xπ, m, ls; isinplace = isinplace, ongpu = ongpu, massmatrix = massmatrix)

function PeriodicOrbitTrapProblem(prob_vf,
									ϕ::vectype,
									xπ::vectype,
									m::Union{Int, vecmesh},
									N::Int,
									ls::AbstractLinearSolver = DefaultLS();
									ongpu = false,
									massmatrix = nothing,
									updateSectionEveryStep::Int = 0,
									jacobian::Symbol = :Dense) where {vectype, vecmesh <: AbstractVector}
	M = m isa Number ? m : length(m) + 1
	# we use 0 * ϕ to create a copy filled with zeros, this is useful to keep the types
	prob = PeriodicOrbitTrapProblem(prob_vf = prob_vf,
									ϕ = similar(ϕ, N*M),
									xπ = similar(xπ, N*M),
									M = M,
									mesh = TimeMesh(m),
									N = N,
									linsolver = ls,
									ongpu = ongpu,
									massmatrix = massmatrix,
									updateSectionEveryStep = updateSectionEveryStep,
									jacobian = jacobian)

	prob.xπ .= 0
	prob.ϕ .= 0

	prob.xπ[1:length(xπ)] .= xπ
	prob.ϕ[1:length(ϕ)] .= ϕ
	return prob
end

# PeriodicOrbitTrapProblem(F, J, ϕ::vectype, xπ::vectype, m::Union{Int, vecmesh}, N::Int, ls::AbstractLinearSolver = DefaultLS(); ongpu = false, adaptmesh = false, massmatrix = nothing) where {vectype, vecmesh <: AbstractVector} = PeriodicOrbitTrapProblem(F, J, nothing, ϕ, xπ, m, N, ls; isinplace = isinplace, ongpu = ongpu, massmatrix = massmatrix)

PeriodicOrbitTrapProblem(prob_vf,
						m::Union{Int, vecmesh},
						N::Int,
						ls::AbstractLinearSolver = DefaultLS();
						ongpu = false,
					 	adaptmesh = false,
						massmatrix = nothing) where {vecmesh <: AbstractVector} = PeriodicOrbitTrapProblem(prob_vf, zeros(N*(m isa Number ? m : length(m) + 1)), zeros(N*(m isa Number ? m : length(m) + 1)), m, N, ls; ongpu = ongpu, massmatrix = massmatrix)

# these functions extract the last component of the periodic orbit guess
@inline extractPeriodFDTrap(pb::PeriodicOrbitTrapProblem, x::AbstractVector) = onGpu(pb) ? x[end:end] : x[end]
# these functions extract the time slices components
getTimeSlices(x::AbstractVector, N, M) = @views reshape(x[1:end-1], N, M)
getTimeSlices(pb::PeriodicOrbitTrapProblem, x) = getTimeSlices(x, pb.N, pb.M)

# do not type h::Number because this will annoy using CUDA
function POTrapScheme!(pb::AbstractPOFDProblem, dest, u1, u2, du1, du2, par, h, tmp, linear::Bool = true; applyf::Bool = true)
	# this function implements the basic implicit scheme used for the time integration
	# because this function is called in a cyclic manner, we save in the variable tmp the value of F(u2) in order to avoid recomputing it in a subsequent call
	# basically tmp is F(u2)
	if linear
		dest .= tmp
		if applyf
			# tmp <- pb.F(u1, par)
			applyF(pb, tmp, u1, par) #TODO this line does not almost seem to be type stable in code_wartype, gives @_11::Union{Nothing, Tuple{Int64,Int64}}
		else
			applyJ(pb, tmp, u1, par, du1)
		end
		if hasmassmatrix(pb)
			dest .= pb.massmatrix * (du1 .- du2) .- h .* (dest .+ tmp)
		else
			dest .= @. (du1 - du2) - h * (dest + tmp)
		end
	else
		dest .-= h .* tmp
		# tmp <- pb.F(u1, par)
		applyF(pb, tmp, u1, par)
		dest .-= h .* tmp
	end
end
POTrapScheme!(pb::AbstractPOFDProblem, dest, u1, u2, par, h, tmp, linear::Bool = true; applyf::Bool = true) = POTrapScheme!(pb, dest, u1, u2, u1, u2, par, h, tmp, linear; applyf = applyf)

"""
This function implements the functional for finding periodic orbits based on finite differences using the Trapezoidal rule. It works for inplace / out of place vector fields `pb.F`
"""
function POTrapFunctional!(pb::AbstractPOFDProblem, out, u, par)
		M, N = size(pb)
		T = extractPeriodFDTrap(pb, u)

		uc = getTimeSlices(pb, u)
		outc = getTimeSlices(pb, out)

		# outc[:, M] plays the role of tmp until it is used just after the for-loop
		@views applyF(pb, outc[:, M], uc[:, M-1], par)

		h = T * getTimeStep(pb, 1)
		# https://docs.julialang.org/en/v1/manual/performance-tips/#man-performance-column-major
		# fastest is to do out[:, i] = x
		@views POTrapScheme!(pb, outc[:, 1], uc[:, 1], uc[:, M-1], par, h/2, outc[:, M])

		for ii in 2:M-1
			h = T * getTimeStep(pb, ii)
			# this function avoids computing F(uc[:, ii]) twice
			@views POTrapScheme!(pb, outc[:, ii], uc[:, ii], uc[:, ii-1], par, h/2, outc[:, M])
		end

		# closure condition ensuring a periodic orbit
		outc[:, M] .= @views uc[:, M] .- uc[:, 1]

		# this is for CuArrays.jl to work in the mode allowscalar(false)
		if onGpu(pb)
			return @views vcat(out[1:end-1], dot(u[1:end-1], pb.ϕ) - dot(pb.xπ, pb.ϕ)) # this is the phase condition
		else
			out[end] = @views dot(u[1:end-1], pb.ϕ) - dot(pb.xπ, pb.ϕ) #dot(u0c[:, 1] .- pb.xπ, pb.ϕ)
			return out
		end
end

"""
Matrix free expression of the Jacobian of the problem for computing periodic obits when evaluated at `u` and applied to `du`.
"""
function POTrapFunctionalJac!(pb::AbstractPOFDProblem, out, u, par, du)
	M, N = size(pb)
	T  = extractPeriodFDTrap(pb, u)
	dT = extractPeriodFDTrap(pb, du)

	uc = getTimeSlices(pb, u)
	outc = getTimeSlices(pb, out)
	duc = getTimeSlices(pb, du)

	# compute the cyclic part
	@views Jc(pb, outc, u[1:end-1-N], par, T, du[1:end-N-1], outc[:, M])

	# outc[:, M] plays the role of tmp until it is used just after the for-loop
	tmp = @view outc[:, M]

	# we now compute the partial derivative w.r.t. the period T
	@views applyF(pb, tmp, uc[:, M-1], par)

	h = dT * getTimeStep(pb, 1)
	@views POTrapScheme!(pb, outc[:, 1], uc[:, 1], uc[:, M-1], par, h/2, tmp, false)
	for ii in 2:M-1
		h = dT * getTimeStep(pb, ii)
		@views POTrapScheme!(pb, outc[:, ii], uc[:, ii], uc[:, ii-1], par, h/2, tmp, false)
	end

	# closure condition ensuring a periodic orbit
	outc[:, M] .= @views duc[:, M] .- duc[:, 1]

	# this is for CuArrays.jl to work in the mode allowscalar(false)
	if onGpu(pb)
		return @views vcat(out[1:end-1], dot(du[1:end-1], pb.ϕ))
	else
		out[end] = @views dot(du[1:end-1], pb.ϕ)
		return out
	end
end

(pb::PeriodicOrbitTrapProblem)(u::AbstractVector, par) = POTrapFunctional!(pb, similar(u), u, par)
(pb::PeriodicOrbitTrapProblem)(u::AbstractVector, par, du) = POTrapFunctionalJac!(pb, similar(du), u, par, du)

####################################################################################################
# Matrix free expression of matrices related to the Jacobian Matrix of the PO functional
"""
Function to compute the Matrix-Free version of Aγ, see docs for its expression.
"""
function Aγ!(pb::PeriodicOrbitTrapProblem, outc, u0::AbstractVector, par, du::AbstractVector; γ = 1)
	# u0 of size N * M + 1
	# du of size N * M
	M, N = size(pb)
	T = extractPeriodFDTrap(pb, u0)
	u0c = getTimeSlices(pb, u0)

	# compute the cyclic part
	@views Jc(pb, outc, u0[1:end-1-N], par, T, du[1:end-N], outc[:, M])

	# closure condition ensuring a periodic orbit
	duc = reshape(du, N, M)
	outc[:, M] .= @views duc[:, M] .- γ .* duc[:, 1]
	return nothing
end

"""
Function to compute the Matrix-Free version of the cyclic matrix Jc, see docs for its expression.
"""
function Jc(pb::PeriodicOrbitTrapProblem, outc::AbstractMatrix, u0::AbstractVector, par, T, du::AbstractVector, tmp)
	# tmp plays the role of buffer array
	# u0 of size N * (M - 1)
	# du of size N * (M - 1)
	# outc of size N * M
	M, N = size(pb)

	u0c = reshape(u0, N, M-1)
	duc = reshape(du, N, M-1)

	@views applyJ(pb, tmp, u0c[:, M-1], par, duc[:, M-1])

	h = T * getTimeStep(pb, 1)
	@views POTrapScheme!(pb, outc[:, 1], u0c[:, 1], u0c[:, M-1],
										 duc[:, 1], duc[:, M-1], par, h/2, tmp, true; applyf = false)

	for ii in 2:M-1
		h = T * getTimeStep(pb, ii)
		@views POTrapScheme!(pb, outc[:, ii], u0c[:, ii], u0c[:, ii-1],
											  duc[:, ii], duc[:, ii-1], par, h/2, tmp, true; applyf = false)
	end

	# we also return a Vector version of outc
	return vec(outc)
end

function Jc(pb::PeriodicOrbitTrapProblem, u0::AbstractVector, par, du::AbstractVector)
	M, N = size(pb)
	T = extractPeriodFDTrap(pb, u0)

	out  = similar(du)
	outc = reshape(out, N, M-1)
	tmp  = similar(view(outc, :, 1))
	return @views Jc(pb, outc, u0[1:end-1-N], par, T, du, tmp)
end
####################################################################################################
"""
Matrix by blocks expression of the Jacobian for the PO functional computed at the space-time guess: `u0`
"""
function jacobianPOTrapBlock(pb::PeriodicOrbitTrapProblem, u0::AbstractVector, par; γ = 1)
	# extraction of various constants
	M, N = size(pb)

	Aγ = BlockArray(spzeros(M * N, M * N), N * ones(Int64, M),  N * ones(Int64, M))
	cylicPOTrapBlock!(pb, u0, par, Aγ)

	In = spdiagm( 0 => ones(N))
	Aγ[Block(M, 1)] = -γ * In
	Aγ[Block(M, M)] = In
	return Aγ
end

"""
This function populates Jc with the cyclic matrix using the different Jacobians
"""
function cylicPOTrapBlock!(pb::PeriodicOrbitTrapProblem, u0::AbstractVector, par, Jc::BlockArray)
	# extraction of various constants
	M, N = size(pb)
	T = extractPeriodFDTrap(pb, u0)

	In = getMassMatrix(pb)

	u0c = getTimeSlices(pb, u0)
	outc = similar(u0c)

	tmpJ = @views jacobian(pb.prob_vf, u0c[:, 1], par)

	h = T * getTimeStep(pb, 1)
	Jn = In - (h/2) .* tmpJ
	Jc[Block(1, 1)] = Jn

	# we could do a Jn .= -I .- ... but we want to allow the sparsity pattern to vary
	Jn = @views -In - (h/2) .* jacobian(pb.prob_vf, u0c[:, M-1], par)
	Jc[Block(1, M-1)] = Jn

	for ii in 2:M-1
		h = T * getTimeStep(pb, ii)
		Jn = -In - (h/2) .* tmpJ
		Jc[Block(ii, ii-1)] = Jn

		tmpJ = @views jacobian(pb.prob_vf, u0c[:, ii], par)

		Jn = In - (h/2) .* tmpJ
		Jc[Block(ii, ii)] = Jn
	end
	return Jc
end

function cylicPOTrapBlock(pb::PeriodicOrbitTrapProblem, u0::AbstractVector, par)
	# extraction of various constants
	M, N = size(pb)
	Jc = BlockArray(spzeros((M - 1) * N, (M - 1) * N), N * ones(Int64, M-1),  N * ones(Int64, M-1))
	cylicPOTrapBlock!(pb, u0, par, Jc)
end

cylicPOTrapSparse(pb::PeriodicOrbitTrapProblem, orbitguess0, par) = blockToSparse(cylicPOTrapBlock(pb, orbitguess0, par))

"""
This method returns the jacobian of the functional G encoded in PeriodicOrbitTrapProblem using a Sparse representation.
"""
function (pb::PeriodicOrbitTrapProblem)(::Val{:JacFullSparse}, u0::AbstractVector, par; γ = 1, δ = convert(eltype(u0), 1e-9))
	# extraction of various constants
	M, N = size(pb)
	T = extractPeriodFDTrap(pb, u0)
	AγBlock = jacobianPOTrapBlock(pb, u0, par; γ = γ)

	# we now set up the last line / column
	@views ∂TGpo = (pb(vcat(u0[1:end-1], T + δ), par) .- pb(u0, par)) ./ δ

	# this is "bad" for performance. Get converted to SparseMatrix at the next line
	Aγ = blockToSparse(AγBlock) # most of the computing time is here!!
	@views Aγ = hcat(Aγ, ∂TGpo[1:end-1])
	Aγ = vcat(Aγ, spzeros(1, N * M + 1))

	Aγ[N*M+1, 1:length(pb.ϕ)] .=  pb.ϕ
	Aγ[N*M+1, N*M+1] = ∂TGpo[end]
	return Aγ
end

"""
This method returns the jacobian of the functional G encoded in PeriodicOrbitTrapProblem using an inplace update. In case where the passed matrix J0 is a sparse one, it updates J0 inplace assuming that the sparsity pattern of J0 and dG(orbitguess0) are the same.
"""
@views function (pb::PeriodicOrbitTrapProblem)(::Val{:JacFullSparseInplace}, J0::Tj, u0::AbstractVector, par; γ = 1, δ = convert(eltype(u0), 1e-9)) where Tj
		M, N = size(pb)
		T = extractPeriodFDTrap(pb, u0)

		In = getMassMatrix(pb, ~(Tj <: SparseMatrixCSC))

		u0c = getTimeSlices(pb, u0)
		outc = similar(u0c)

		tmpJ = jacobian(pb.prob_vf, u0c[:, 1], par)

		h = T * getTimeStep(pb, 1)
		Jn = In - (h/2) .* tmpJ
		# setblock!(Jc, Jn, 1, 1)
		J0[1:N, 1:N] .= Jn

		Jn .= -In .- (h/2) .* jacobian(pb.prob_vf, u0c[:, M-1], par)
		# setblock!(Jc, Jn, 1, M-1)
		J0[1:N, (M-2)*N+1:(M-1)*N] .= Jn

		for ii in 2:M-1
			h = T * getTimeStep(pb, ii)
			@. Jn = -In - h/2 * tmpJ
			# the next lines cost the most
			# setblock!(Jc, Jn, ii, ii-1)
			J0[(ii-1)*N+1:(ii)*N, (ii-2)*N+1:(ii-1)*N] .= Jn

			tmpJ .= jacobian(pb.prob_vf, u0c[:, ii], par)

			@. Jn = In - h/2 * tmpJ
			# setblock!(Jc, Jn, ii, ii)
			J0[(ii-1)*N+1:(ii)*N, (ii-1)*N+1:(ii)*N] .= Jn
		end

		# setblock!(Aγ, -γ * In, M, 1)
		# useless to update:
			# J0[(M-1)*N+1:(M)*N, (1-1)*N+1:(1)*N] .= -In
		# setblock!(Aγ,  In,     M, M)
		# useless to update:
			# J0[(M-1)*N+1:(M)*N, (M-1)*N+1:(M)*N] .= In

		# we now set up the last line / column
		∂TGpo = (pb(vcat(u0[1:end-1], T + δ), par) .- pb(u0, par)) ./ δ
		J0[:, end] .=  ∂TGpo

		# this following does not depend on u0, so it does not change. However we update it in case the caller updated the section somewhere else
		J0[N*M+1, 1:length(pb.ϕ)] .=  pb.ϕ

		return J0
end


@views function (pb::PeriodicOrbitTrapProblem)(::Val{:JacFullSparseInplace}, J0, u0::AbstractVector, par, indx; γ = 1, δ = convert(eltype(u0), 1e-9), updateborder = true)
	M, N = size(pb)
	T = extractPeriodFDTrap(pb, u0)

	In = getMassMatrix(pb)

	u0c = getTimeSlices(pb, u0)
	outc = similar(u0c)

	tmpJ = jacobian(pb.prob_vf, u0c[:, 1], par)

	h = T * getTimeStep(pb, 1)
	Jn = In - tmpJ * (h/2)

	# setblock!(Jc, Jn, 1, 1)
	J0.nzval[indx[1, 1]] .= Jn.nzval

	Jn .= -In .- jacobian(pb.prob_vf, u0c[:, M-1], par) .* (h/2)
	# setblock!(Jc, Jn, 1, M-1)
	J0.nzval[indx[1, M-1]] .= Jn.nzval

	for ii in 2:M-1
		h = T * getTimeStep(pb, ii)
		@. Jn = -In - tmpJ * (h/2)
		# the next lines cost the most
		# setblock!(Jc, Jn, ii, ii-1)
		J0.nzval[indx[ii, ii-1]] .= Jn.nzval

		tmpJ .= jacobian(pb.prob_vf, u0c[:, ii], par)# * (h/2)

		@. Jn = In -  tmpJ * (h/2)
		# setblock!(Jc, Jn, ii, ii)
		J0.nzval[indx[ii,ii]] .= Jn.nzval
	end

	# setblock!(Aγ, -γ * In, M, 1)
	# useless to update:
		# J0[(M-1)*N+1:(M)*N, (1-1)*N+1:(1)*N] .= -In
	# setblock!(Aγ,  In,     M, M)
	# useless to update:
		# J0[(M-1)*N+1:(M)*N, (M-1)*N+1:(M)*N] .= In

	if updateborder
		# we now set up the last line / column
		∂TGpo = (pb(vcat(u0[1:end-1], T + δ), par) .- pb(u0, par)) ./ δ
		J0[:, end] .=  ∂TGpo

		# this following does not depend on u0, so it does not change. However we update it in case the caller updated the section somewhere else
		J0[N*M+1, 1:length(pb.ϕ)] .=  pb.ϕ
	end

	return J0
end

function (pb::PeriodicOrbitTrapProblem)(::Val{:JacCyclicSparse}, u0::AbstractVector, par, γ = 1)
	# extraction of various constants
	N = pb.N
	AγBlock = jacobianPOTrapBlock(pb, u0, par; γ = γ)

	# this is bad for performance. Get converted to SparseMatrix at the next line
	Aγ = blockToSparse(AγBlock) # most of the computing time is here!!
	# the following line is bad but still less costly than the previous one
	return Aγ[1:end-N, 1:end-N]
end

function (pb::PeriodicOrbitTrapProblem)(::Val{:BlockDiagSparse}, u0::AbstractVector, par)
	# extraction of various constants
	M, N = size(pb)
	T = extractPeriodFDTrap(pb, u0)

	A_diagBlock = BlockArray(spzeros(M * N, M * N), N * ones(Int64, M),  N * ones(Int64, M))

	In = getMassMatrix(pb)

	u0c = reshape(u0[1:end-1], N, M)
	outc = similar(u0c)

	h = T * getTimeStep(pb, 1)
	@views Jn = In - h/2 .* jacobian(pb.prob_vf, u0c[:, 1], par)
	A_diagBlock[Block(1, 1)] = Jn

	for ii in 2:M-1
		h = T * getTimeStep(pb, ii)
		@views Jn = In - h/2 .* jacobian(pb.prob_vf, u0c[:, ii], par)
		A_diagBlock[Block(ii, ii)]= Jn
	end
	A_diagBlock[Block(M, M)]= In

	A_diag_sp = blockToSparse(A_diagBlock) # most of the computing time is here!!
	return A_diag_sp
end
####################################################################################################
# Utils
"""
$(SIGNATURES)

Compute the full periodic orbit associated to `x`. Mainly for plotting purposes.
"""
@views function getPeriodicOrbit(prob::AbstractPOFDProblem, u::AbstractVector, p)
	T = getPeriod(prob, u, p)
	M, N = size(prob)
	uv = u[1:end-1]
	uc = reshape(uv, N, M)
	return SolPeriodicOrbit(t = cumsum(T .* collect(prob.mesh)), u = uc)
end

"""
$(SIGNATURES)

Compute the period of the periodic orbit associated to `x`.
"""
@inline getPeriod(prob::PeriodicOrbitTrapProblem, x, p) = extractPeriodFDTrap(prob, x)

"""
$(SIGNATURES)

Compute `norm(du/dt)`
"""
@views function getTimeDiff(pb::PeriodicOrbitTrapProblem, u)
	M, N = size(pb)
	T = extractPeriodFDTrap(pb, u)
	uc = reshape(u[1:end-1], N, M)
	return [norm(uc[:,ii+1].-uc[:,ii]) * T/M for ii in 1:M-1]
end

"""
$(SIGNATURES)

Compute the amplitude of the periodic orbit associated to `x`. The keyword argument `ratio = 1` is used as follows. If `length(x) = 1 + ratio * n`, the call returns the amplitude over `x[1:n]`.
"""
@views function getAmplitude(prob::PeriodicOrbitTrapProblem, x::AbstractVector, p; ratio = 1)
	n = div(length(x)-1, ratio)
	_max = maximum(x[1:n])
	_min = minimum(x[1:n])
	return maximum(_max .- _min)
end

"""
$(SIGNATURES)

Compute the maximum of the periodic orbit associated to `x`. The keyword argument `ratio = 1` is used as follows. If `length(x) = 1 + ratio * n`, the call returns the amplitude over `x[1:n]`.
"""
@views function getMaximum(prob::PeriodicOrbitTrapProblem, x::AbstractVector, p; ratio = 1)
	n = div(length(x)-1, ratio)
	return maximum(x[1:n])
end

# this function updates the section during the continuation run
@views function updateSection!(prob::PeriodicOrbitTrapProblem, x, par; stride = 0)
	M, N = size(prob)
	xc = getTimeSlices(prob, x)
	T = extractPeriodFDTrap(prob, x)

	# update the reference point
	prob.xπ .= x[1:end-1]

	# update the normals
	for ii in 0:M-1
		# ii2 = (ii+1)<= M ? ii+1 : ii+1-M
		applyF(prob, prob.ϕ[ii*N+1:ii*N+N], xc[:, ii+1], par)
		prob.ϕ[ii*N+1:ii*N+N] ./= M
	end

	return true
end
####################################################################################################
# Linear solvers for the jacobian of the functional G implemented by PeriodicOrbitTrapProblem
# composite type to encode the Aγ Operator and its associated cyclic matrix
abstract type AbstractPOTrapAγOperator end

# Matrix Free implementation of the operator Aγ
@with_kw mutable struct AγOperatorMatrixFree{Tvec, Tpb, Tpar} <: AbstractPOTrapAγOperator
	orbitguess::Tvec = zeros(1)				# point at which Aγ is evaluated, of size N * M + 1
	prob::Tpb = nothing						# PO functional, used when is_matrix_free = true
	par::Tpar = nothing						# parameters,    used when is_matrix_free = true
end

# implementation of Aγ which catches the LU decomposition of the cyclic matrix
@with_kw mutable struct AγOperatorLU{Tjc, Tpb} <: AbstractPOTrapAγOperator
	N::Int64 = 0							# dimension of time slice
	Jc::Tjc	= lu(spdiagm(0 => ones(1)))	    # lu factorisation of the cyclic matrix
	prob::Tpb = nothing						# PO functional
end

@with_kw struct AγOperatorSparseInplace{Tjc, Tjcf, Tind, Tpb} <: AbstractPOTrapAγOperator
	Jc::Tjc	=  nothing		# cyclic matrix
	Jcfact::Tjcf = nothing	# factorisation of Jc
	indx::Tind = nothing	# indices associated to the sparsity of Jc
	prob::Tpb = nothing		# PO functional
end

# functions to update the cyclic matrix
function (A::AγOperatorMatrixFree)(orbitguess::AbstractVector, par)
	copyto!(A.orbitguess, orbitguess)
	# update par for Matrix-Free
	A.par = par
	return A
end

function (A::AγOperatorLU)(orbitguess::AbstractVector, par)
	# we store the lu decomposition of the newly computed cyclic matrix
	A.Jc = SparseArrays.lu(cylicPOTrapSparse(A.prob, orbitguess, par))
	A
end

function (A::AγOperatorSparseInplace)(orbitguess::AbstractVector, par)
	# compute the cyclic matrix
	A.prob(Val(:JacFullSparseInplace), A.Jc, orbitguess, par, A.indx; updateborder = false)
	# update the Lu decomposition
	lu!(A.Jcfact, A.Jc)
	return A
end

@views function apply(A::AγOperatorSparseInplace, dx)
	out = similar(dx)
	M, N = size(A.prob)
	out1 = apply(A.Jc, dx[1:end-N])
	return vcat(out1, -dx[1:N] .+ dx[end-N+1:end])
end

# linear solvers designed specifically for AbstractPOTrapAγOperator
# this function is called whenever one wants to invert Aγ
@with_kw struct AγLinearSolver{Tls} <: AbstractLinearSolver
	# Linear solver to invert the cyclic matrix Jc contained in Aγ
	linsolver::Tls = DefaultLS()
end

@views function _combineSolutionAγLinearSolver(rhs, xbar, N)
	x = similar(rhs)
	x[1:end-N] .= xbar
	x[end-N+1:end] .= x[1:N] .+ rhs[end-N+1:end]
	return x
end

@views function (ls::AγLinearSolver)(A::AγOperatorMatrixFree, rhs)
	# dimension of a time slice
	N = A.prob.N
	# we invert the cyclic part Jc of Aγ
	xbar, flag, numiter = ls.linsolver(dx -> Jc(A.prob, A.orbitguess, A.par, dx), rhs[1:end - N])
	!flag && @warn "Matrix Free solver for Aγ did not converge"
	return _combineSolutionAγLinearSolver(rhs, xbar, N), flag, numiter
end

@views function (ls::AγLinearSolver)(A::AγOperatorLU, rhs)
	# dimension of a time slice
	N = A.N
	xbar, flag, numiter = ls.linsolver(A.Jc, rhs[1:end - N])
	!flag && @warn "Sparse solver for Aγ did not converge"
	return _combineSolutionAγLinearSolver(rhs, xbar, N), flag, numiter
end

@views function (ls::AγLinearSolver)(A::AγOperatorSparseInplace, rhs)
	# dimension of a time slice
	N = A.prob.N
	# we invert the cyclic part Jc of Aγ
	xbar, flag, numiter = ls.linsolver(A.Jcfact, rhs[1:end - N])
	!flag && @warn "Sparse solver for Aγ did not converge"
	return _combineSolutionAγLinearSolver(rhs, xbar, N), flag, numiter
end

####################################################################################################
# The following structure encodes the jacobian of a PeriodicOrbitTrapProblem which eases the use of PeriodicOrbitTrapBLS. It is made so that accessing the cyclic matrix Jc or Aγ is easier. It is combined with a specific linear solver. It is also a convenient structure for the computation of Floquet multipliers. Therefore, it is only used in the method continuationPOTrap
@with_kw struct POTrapJacobianBordered{T∂, Tag <: AbstractPOTrapAγOperator}
	∂TGpo::T∂ = nothing		# derivative of the PO functional G w.r.t. T
	Aγ::Tag					# Aγ Operator involved in the Jacobian of the PO functional
end

# this function is called whenever the jacobian of G has to be updated
function (J::POTrapJacobianBordered)(u0::AbstractVector, par; δ = convert(eltype(u0), 1e-9))
	T = extractPeriodFDTrap(J.Aγ.prob, u0)
	# we compute the derivative of the problem w.r.t. the period TODO: remove this or improve!!
	# TODO REMOVE CE vcat!
	@views J.∂TGpo .= (J.Aγ.prob(vcat(u0[1:end-1], T + δ), par) .- J.Aγ.prob(u0, par)) ./ δ

	J.Aγ(u0, par) # update Aγ

	# return J, needed to properly call the linear solver.
	return J
end

# this is to use BorderingBLS with checkPrecision = true
#        ┌             ┐
#  J =   │  Aγ   ∂TGpo │
#        │  ϕ'     *   │
#        └             ┘
@views function apply(J::POTrapJacobianBordered, dx)
	# this function would be much more efficient if
	# we call J.Aγ.prob(x, par, dx) but we dont have (x, par)
	out1 = apply(J.Aγ, dx[1:end-1])
	out1 .+= J.∂TGpo[1:end-1] .* dx[end]
	return vcat(out1, dot(J.Aγ.prob.ϕ, dx[1:end-1]) + dx[end] * J.∂TGpo[end])

	throw("Not implemented. If you use the bordered linear solver BorderingBLS, please use the option `checkPrecision = false`")
end
####################################################################################################
# linear solver for the PO functional, akin to a bordered linear solver
@with_kw struct PeriodicOrbitTrapBLS{Tl} <: AbstractLinearSolver
	linsolverbls::Tl = BorderingBLS(solver = AγLinearSolver(), checkPrecision = false)	# linear solver
end

# Linear solver associated to POTrapJacobianBordered
function (ls::PeriodicOrbitTrapBLS)(J::POTrapJacobianBordered, rhs)
	# we solve the bordered linear system as follows
	dX, dl, flag, liniter = @views ls.linsolverbls(J.Aγ, J.∂TGpo[1:end-1],
	 										J.Aγ.prob.ϕ, J.∂TGpo[end],
										   rhs[1:end-1], rhs[end])
	return vcat(dX, dl), flag, sum(liniter)
end

# One could think that by implementing (ls::PeriodicOrbitTrapBLS)(J::POTrapJacobianBLS, rhs1, rhs2), we could speed up the computation of the linear Bordered system arising in the continuation process. However, we can note that this speed up would be observed only if a factorization of J.Aγ is available like an LU one. When such factorization is available, it is automatically stored as such in J.Aγ and so no speed up would be gained by implementing (ls::PeriodicOrbitTrapBLS)(J::POTrapJacobianBLS, rhs1, rhs2)

##########################
# problem wrappers
residual(prob::WrapPOTrap, x, p) = prob.prob(x, p)
jacobian(prob::WrapPOTrap, x, p) = prob.jacobian(x, p)
getPeriodicOrbit(prob::WrapPOTrap, u::AbstractVector, p) = getPeriodicOrbit(prob.prob, u, p)
##########################
# newton wrappers
function _newtonTrap(probPO::PeriodicOrbitTrapProblem,
				orbitguess,
				options::NewtonPar;
				defOp::Union{Nothing, DeflationOperator{T, Tf, vectype}} = nothing,
				kwargs...) where {T, Tf, vectype}
	# this hack is for the test to work with CUDA
	@assert sum(extractPeriodFDTrap(probPO, orbitguess)) >= 0 "The guess for the period should be positive"
	jacobianPO = probPO.jacobian
	@assert jacobianPO in (:Dense, :DenseAD, :FullLU, :BorderedLU, :FullMatrixFree, :BorderedMatrixFree, :FullSparseInplace, :BorderedSparseInplace, :FullMatrixFreeAD) "This jacobian is not defined. Please choose another one."
	M, N = size(probPO)

	if jacobianPO in (:Dense, :DenseAD, :FullLU, :FullMatrixFree, :FullSparseInplace, :FullMatrixFreeAD)
		if jacobianPO == :FullLU
			jac = (x, p) -> probPO(Val(:JacFullSparse), x, p)
		elseif jacobianPO == :FullSparseInplace
			# sparse matrix to hold the jacobian
			_J =  probPO(Val(:JacFullSparse), orbitguess, getParams(probPO.prob_vf))
			_indx = getBlocks(_J, N, M)
			# inplace modification of the jacobian _J
			jac = (x, p) -> probPO(Val(:JacFullSparseInplace), _J, x, p, _indx)
		elseif jacobianPO == :Dense
			_J =  probPO(Val(:JacFullSparse), orbitguess, getParams(probPO.prob_vf)) |> Array
			jac = (x, p) -> probPO(Val(:JacFullSparseInplace), _J, x, p)
		elseif jacobianPO == :DenseAD
			jac = (x, p) -> ForwardDiff.jacobian(z -> probPO(z, p), x)
		elseif jacobianPO == :FullMatrixFreeAD
			jac = (x, p) -> dx -> ForwardDiff.derivative(t -> probPO(x .+ t .* dx, p), 0)
		else
		 	jac = (x, p) -> ( dx -> probPO(x, p, dx))
		end

		# define a problem to call newton
		prob = WrapPOTrap(probPO, jac, orbitguess, getParams(probPO.prob_vf), getLens(probPO.prob_vf), nothing, nothing)

		if isnothing(defOp)
			return newton(prob, options; kwargs...)
			# return newton(probPO, jac, orbitguess, par, options; kwargs...)
		else
			# return newton(probPO, jac, orbitguess, par, options, defOp; kwargs...)
			return newton(prob, defOp, options; kwargs...)
		end
	else # bordered linear solvers
		if jacobianPO == :BorderedLU
			Aγ = AγOperatorLU(N = N, Jc = lu(spdiagm( 0 => ones(N * (M - 1)) )), prob = probPO)
			# linear solver
			lspo = PeriodicOrbitTrapBLS()
		elseif jacobianPO == :BorderedSparseInplace
			_J =  probPO(Val(:JacCyclicSparse), orbitguess, getParams(probPO.prob_vf))
			_indx = getBlocks(_J, N, M-1)
			# inplace modification of the jacobian _J
			Aγ = AγOperatorSparseInplace(Jc = _J,  Jcfact = lu(_J), prob = probPO, indx = _indx)
			lspo = PeriodicOrbitTrapBLS()

		else	# :BorderedMatrixFree
			Aγ = AγOperatorMatrixFree(prob = probPO, orbitguess = zeros(N * M + 1), par = getParams(probPO.prob_vf))
			# linear solver
			lspo = PeriodicOrbitTrapBLS(BorderingBLS(solver = AγLinearSolver(options.linsolver), checkPrecision = false))
		end

		jacPO = POTrapJacobianBordered(zeros(N * M + 1), Aγ)

		prob = WrapPOTrap(probPO, jacPO, orbitguess, getParams(probPO.prob_vf), getLens(probPO.prob_vf), nothing, nothing)

		if isnothing(defOp)
			return newton(prob, (@set options.linsolver = lspo); kwargs...)
		else
			return newton(prob, defOp, (@set options.linsolver = lspo); kwargs...)
		end
	end
end

"""
$(SIGNATURES)

This is the Krylov-Newton Solver for computing a periodic orbit using a functional G based on Finite Differences and a Trapezoidal rule.

# Arguments:
- `prob` a problem of type [`PeriodicOrbitTrapProblem`](@ref) encoding the functional G
- `orbitguess` a guess for the periodic orbit where `orbitguess[end]` is an estimate of the period of the orbit. It should be a vector of size `N * M + 1` where `M` is the number of time slices, `N` is the dimension of the phase space. This must be compatible with the numbers `N, M` in `prob`.
- `par` parameters to be passed to the functional
- `options` same as for the regular `newton` method
$DocStrjacobianPOTrap
"""
newton(probPO::PeriodicOrbitTrapProblem,
		orbitguess,
		options::NewtonPar;
		kwargs...) = _newtonTrap(probPO, orbitguess, options; defOp = nothing, kwargs...)

"""
	$(SIGNATURES)

This function is similar to `newton(probPO, orbitguess, options, jacobianPO; kwargs...)` except that it uses deflation in order to find periodic orbits different from the ones stored in `defOp`. We refer to the mentioned method for a full description of the arguments. The current method can be used in the vicinity of a Hopf bifurcation to prevent the Newton-Krylov algorithm from converging to the equilibrium point.
"""
newton(probPO::PeriodicOrbitTrapProblem,
		orbitguess::vectype,
		defOp::DeflationOperator{Tp, Tdot, T, vectype},
		options::NewtonPar;
		kwargs...) where {Tp, Tdot, T, vectype} = _newtonTrap(probPO, orbitguess, options; defOp = defOp, kwargs...)

####################################################################################################
# continuation wrapper
"""
	$(SIGNATURES)

This is the continuation routine for computing a periodic orbit using a functional G based on Finite Differences and a Trapezoidal rule.

# Arguments
- `prob::PeriodicOrbitTrapProblem` encodes the functional G
- `orbitguess` a guess for the periodic orbit where `orbitguess[end]` is an estimate of the period of the orbit. It could be a vector of size `N * M + 1` where `M` is the number of time slices, `N` is the dimension of the phase space. This must be compatible with the numbers `N, M` in `prob`.
- `alg` conntinuation algorithm
- `contParams` same as for the regular [`continuation`](@ref) method
- `linearAlgo` same as in [`continuation`](@ref)

# Keywords arguments
- `eigsolver` specify an eigen solver for the computation of the Floquet exponents, defaults to `FloquetQaD`

$DocStrjacobianPOTrap

Note that by default, the method prints the period of the periodic orbit as function of the parameter. This can be changed by providing your `recordFromSolution` argument.
"""
function continuationPOTrap(prob::PeriodicOrbitTrapProblem,
			orbitguess,
			alg::AbstractContinuationAlgorithm,
			contParams::ContinuationPar,
			linearAlgo::AbstractBorderedLinearSolver;
			eigsolver = FloquetQaD(contParams.newtonOptions.eigsolver),
			kwargs...)
	# this hack is for the test to work with CUDA
	@assert sum(extractPeriodFDTrap(prob, orbitguess)) >= 0 "The guess for the period should be positive"
	jacobianPO = prob.jacobian
	@assert jacobianPO in (:Dense, :DenseAD, :FullLU, :FullMatrixFree, :BorderedLU, :BorderedMatrixFree, :FullSparseInplace, :BorderedSparseInplace, :FullMatrixFreeAD) "This jacobian is not defined. Please chose another one."

	M, N = size(prob)
	options = contParams.newtonOptions

	if computeEigenElements(contParams)
		contParams = @set contParams.newtonOptions.eigsolver =
		 eigsolver
	end

	# change the user provided finalise function by passing prob in its parameters
	_finsol = modifyPOFinalise(prob, kwargs, prob.updateSectionEveryStep)
	_recordsol = modifyPORecord(prob, kwargs, getParams(prob.prob_vf), getLens(prob.prob_vf))
	_plotsol = modifyPOPlot(prob, kwargs)

	if jacobianPO in (:Dense, :DenseAD, :FullLU, :FullMatrixFree, :FullSparseInplace, :FullMatrixFreeAD)
		if jacobianPO == :FullLU
			jac = (x, p) -> FloquetWrapper(prob, prob(Val(:JacFullSparse), x, p), x, p)
		elseif jacobianPO == :FullSparseInplace
			# sparse matrix to hold the jacobian
			_J =  prob(Val(:JacFullSparse), orbitguess, getParams(prob.prob_vf))
			_indx = getBlocks(_J, N, M)
			# inplace modification of the jacobian _J
			jac = (x, p) -> (prob(Val(:JacFullSparseInplace), _J, x, p, _indx); FloquetWrapper(prob, _J, x, p));
		elseif jacobianPO == :Dense
			_J =  prob(Val(:JacFullSparse), orbitguess, getParams(prob.prob_vf)) |> Array
			jac = (x, p) -> (prob(Val(:JacFullSparseInplace), _J, x, p); FloquetWrapper(prob, _J, x, p));
		elseif jacobianPO == :DenseAD
			jac = (x, p) -> FloquetWrapper(prob, ForwardDiff.jacobian(z -> prob(z, p), x), x, p)
		elseif jacobianPO == :FullMatrixFreeAD
			jac = (x, p) -> dx -> ForwardDiff.derivative(t->prob(x .+ t .* dx, p), 0)
		else
		 	jac = (x, p) -> FloquetWrapper(prob, x, p)
		end

		# we have to change the Bordered linearsolver to cope with our type FloquetWrapper
		linearAlgo = @set linearAlgo.solver = FloquetWrapperLS(linearAlgo.solver)
		contParams2 = (@set contParams.newtonOptions.linsolver = FloquetWrapperLS(options.linsolver))
		alg = update(alg, contParams2, linearAlgo)

		probwp = WrapPOTrap(prob, jac, orbitguess, getParams(prob.prob_vf), getLens(prob.prob_vf), _plotsol, _recordsol)

		br = continuation(
			probwp, alg,
			contParams2; kwargs...,
			kind = PeriodicOrbitCont(),
			finaliseSolution = _finsol,
			)
	else
		if jacobianPO == :BorderedLU
			Aγ = AγOperatorLU(N = N, Jc = lu(spdiagm( 0 => ones(N * (M - 1)) )), prob = prob)
			# linear solver
			lspo = PeriodicOrbitTrapBLS()
		elseif jacobianPO == :BorderedSparseInplace
			_J =  prob(Val(:JacCyclicSparse), orbitguess, getParams(prob.prob_vf))
			_indx = getBlocks(_J, N, M-1)
			# inplace modification of the jacobian _J
			Aγ = AγOperatorSparseInplace(Jc = _J,  Jcfact = lu(_J), prob = prob, indx = _indx)
			lspo = PeriodicOrbitTrapBLS()

		else	# :BorderedMatrixFree
			Aγ = AγOperatorMatrixFree(prob = prob, orbitguess = zeros(N * M + 1), par = getParams(prob.prob_vf))
			# linear solver
			lspo = PeriodicOrbitTrapBLS(BorderingBLS(solver = AγLinearSolver(options.linsolver), checkPrecision = false))
		end

		jacBD = POTrapJacobianBordered(zeros(N * M + 1), Aγ)
		jacPO = (x, p) -> FloquetWrapper(prob, jacBD(x, p), x, p)

		# we change the linear solver
		contParams = @set contParams.newtonOptions.linsolver = FloquetWrapperLS(lspo)

		# we have to change the Bordered linearsolver to cope with our type FloquetWrapper
		linearAlgo = @set linearAlgo.solver = contParams.newtonOptions.linsolver
		alg = update(alg, contParams, linearAlgo)

		probwp = WrapPOTrap(prob, jacPO, orbitguess, getParams(prob.prob_vf), getLens(prob.prob_vf), _plotsol, _recordsol)

		br = continuation(probwp, alg,
			contParams;#, linearAlgo;
			kwargs...,
			kind = PeriodicOrbitCont(),
			finaliseSolution = _finsol)
	end
	return br
end

"""
$(SIGNATURES)

This is the continuation routine for computing a periodic orbit using a functional G based on Finite Differences and a Trapezoidal rule.

# Arguments
- `prob::PeriodicOrbitTrapProblem` encodes the functional G
- `orbitguess` a guess for the periodic orbit where `orbitguess[end]` is an estimate of the period of the orbit. It could be a vector of size `N * M + 1` where `M` is the number of time slices, `N` is the dimension of the phase space. This must be compatible with the numbers `N, M` in `prob`.
- `alg` continuation algorithm
- `contParams` same as for the regular [`continuation`](@ref) method

# Keyword arguments

- `linearAlgo` same as in [`continuation`](@ref)
$DocStrjacobianPOTrap

Note that by default, the method prints the period of the periodic orbit as function of the parameter. This can be changed by providing your `recordFromSolution` argument.
"""
function continuation(prob::PeriodicOrbitTrapProblem,
					orbitguess,
					alg::AbstractContinuationAlgorithm,
					_contParams::ContinuationPar;
					recordFromSolution = (u, p) -> (period = u[end],),
					linearAlgo = nothing,
					kwargs...)
	_linearAlgo = isnothing(linearAlgo) ?  BorderingBLS(solver = _contParams.newtonOptions.linsolver, checkPrecision = false) : linearAlgo
	return continuationPOTrap(prob, orbitguess, alg, _contParams, _linearAlgo; recordFromSolution = recordFromSolution, kwargs...)
end

####################################################################################################
# function needed for automatic Branch switching from Hopf bifurcation point
function reMake(prob::PeriodicOrbitTrapProblem, prob_vf, hopfpt, ζr::AbstractVector, orbitguess_a, period; kwargs...)
	M = length(orbitguess_a)
	N = length(ζr)

	# append period at the end of the initial guess
	orbitguess_v = reduce(vcat, orbitguess_a)
	orbitguess = vcat(vec(orbitguess_v), period) |> vec

	# update the problem
	probPO = setproperties(prob, N = N, prob_vf = prob_vf, ϕ = zeros(N*M), xπ = zeros(N*M))

	probPO.ϕ[1:N] .= ζr
	probPO.xπ[1:N] .= hopfpt.x0

	return probPO, orbitguess
end

using SciMLBase: AbstractTimeseriesSolution
"""
$(SIGNATURES)

Generate a periodic orbit problem from a solution.

## Arguments
- `pb` a `PeriodicOrbitTrapProblem` which provide basic information, like the number of time slices `M`
- `bifprob` a bifurcation problem to provide the vector field
- `sol` basically, and `ODEProblem
- `period` estimate of the period of the periodic orbit

## Output
- returns a `PeriodicOrbitTrapProblem` and an initial guess.
"""
function generateCIProblem(pb::PeriodicOrbitTrapProblem, bifprob::AbstractBifurcationProblem, sol::AbstractTimeseriesSolution, period)
	u0 = sol(0)
	@assert u0 isa AbstractVector
	N = length(u0)
	probtrap = PeriodicOrbitTrapProblem(M = pb.M, N = N, prob_vf = bifprob, xπ = copy(u0), ϕ = copy(u0))

	M, N = size(probtrap)
	resize!(probtrap.ϕ, N * M)
	resize!(probtrap.xπ, N * M)

	ci = generateSolution(probtrap, t -> sol(t*period/2/pi), period)
	_sol = getPeriodicOrbit(probtrap, ci, nothing)
	probtrap.xπ .= 0
	probtrap.ϕ .= reduce(vcat, [residual(bifprob, _sol.u[:,i], sol.prob.p) for i=1:probtrap.M])

	return probtrap, ci
end
####################################################################################################
