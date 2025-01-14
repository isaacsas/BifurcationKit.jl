abstract type AbstractProblemMinimallyAugmented end
abstract type AbstractCodim2EigenSolver <: AbstractEigenSolver end

getsolver(eig::AbstractCodim2EigenSolver) = eig.eigsolver

for op in (:FoldProblemMinimallyAugmented, :HopfProblemMinimallyAugmented)
	@eval begin
		"""
		$(TYPEDEF)

		Structure to encode Fold / Hopf functional based on a Minimally Augmented formulation.

		# Fields

		$(FIELDS)
		"""
		mutable struct $op{Tprob <: AbstractBifurcationProblem, vectype, T <: Real, S <: AbstractLinearSolver, Sa <: AbstractLinearSolver, Sbd <: AbstractBorderedLinearSolver, Sbda <: AbstractBorderedLinearSolver, Tmass} <: AbstractProblemMinimallyAugmented
			"Functional F(x, p) - vector field - with all derivatives"
			prob_vf::Tprob
			"close to null vector of Jᵗ"
			a::vectype
			"close to null vector of J"
			b::vectype
			"vector zero, to avoid allocating it many times"
			zero::vectype
			"Lyapunov coefficient"
			l1::Complex{T}
			"Cusp test value"
			CP::T
			"Bogdanov-Takens test value"
			BT::T
			"Bautin test values"
			GH::T
			"Zero-Hopf test values"
			ZH::Int
			"linear solver. Used to invert the jacobian of MA functional"
			linsolver::S
			"linear solver for the jacobian adjoint"
			linsolverAdjoint::Sa
			"bordered linear solver"
			linbdsolver::Sbd
			"linear bordered solver for the jacobian adjoint"
			linbdsolverAdjoint::Sbda
			"wether to use the hessian of prob_vf"
			usehessian::Bool
			"wether to use a mass matrix M for studying M∂tu = F(u), default = I"
			massmatrix::Tmass
		end

		@inline hasHessian(pb::$op) = hasHessian(pb.prob_vf)
		@inline isSymmetric(pb::$op) = isSymmetric(pb.prob_vf)
		@inline hasAdjoint(pb::$op) = hasAdjoint(pb.prob_vf)
		@inline hasAdjointMF(pb::$op) = hasAdjointMF(pb.prob_vf)
		@inline isInplace(pb::$op) = isInplace(pb.prob_vf)
		@inline getLens(pb::$op) = getLens(pb.prob_vf)
		jad(pb::$op, args...) = jad(pb.prob_vf, args...)

		# constructor
		function $op(prob, a, b, linsolve::AbstractLinearSolver, linbdsolver = MatrixBLS(); usehessian = true, massmatrix = LinearAlgebra.I)
			# determine scalar type associated to vectors a and b
			α = norm(a) # this is valid, see https://jutho.github.io/KrylovKit.jl/stable/#Package-features-and-alternatives-1
			Ty = eltype(α)
			return $op(prob, a, b, 0*a,
						complex(zero(Ty)),  # l1
						real(one(Ty)),		# cp
						real(one(Ty)),		# bt
						real(one(Ty)),		# gh
						1,					# zh
						linsolve, linsolve, linbdsolver, linbdsolver, usehessian, massmatrix)
		end
	end
end

function detectCodim2Parameters(detectCodim2Bifurcation, options_cont; kwargs...)
	if detectCodim2Bifurcation > 0
		if get(kwargs, :updateMinAugEveryStep, 0) == 0
			@error "You ask for detection of codim 2 bifurcations but passed the option `updateMinAugEveryStep = 0`. The bifurcation detection algorithm may not work faithfully. Please use `updateMinAugEveryStep > 0`."
		end
		return setproperties(options_cont; detectBifurcation = 0, detectEvent = detectCodim2Bifurcation, detectFold = false)
	else
		return options_cont
	end
end
################################################################################
function getBifPointCodim2(br::AbstractResult{Tkind, Tprob}, ind::Int) where {Tkind, Tprob <: Union{FoldMAProblem, HopfMAProblem}}
	prob_ma = br.prob.prob
	Teigvec = getvectortype(br)

	bifpt = br.specialpoint[ind]
	# jacobian at bifurcation point
	if Teigvec <: BorderedArray
		x0 = convert(Teigvec.parameters[1], getVec(bifpt.x, prob_ma))
	else
		x0 = convert(Teigvec, getVec(bifpt.x , prob_ma))
	end

	# parameters for vector field
	p = bifpt.param
	parbif = set(getParams(br), getLens(br), p)
	parbif = set(parbif, getLens(prob_ma), get(bifpt.printsol, getLens(prob_ma)))

	return (x = x0, params = parbif)

end
################################################################################
"""
$(SIGNATURES)

This function turns an initial guess for a Fold/Hopf point into a solution to the Fold/Hopf problem based on a Minimally Augmented formulation.

## Arguments
- `br` results returned after a call to [continuation](@ref Library-Continuation)
- `ind_bif` bifurcation index in `br`

# Optional arguments:
- `options::NewtonPar`, default value `br.contparams.newtonOptions`
- `normN = norm`
- `options` You can pass newton parameters different from the ones stored in `br` by using this argument `options`.
- `bdlinsolver` bordered linear solver for the constraint equation
- `startWithEigen = false` whether to start the Minimally Augmented problem with information from eigen elements.
- `kwargs` keywords arguments to be passed to the regular Newton-Krylov solver

!!! tip "ODE problems"
    For ODE problems, it is more efficient to use the Bordered Linear Solver using the option `bdlinsolver = MatrixBLS()`

!!! tip "startWithEigen"
    It is recommanded that you use the option `startWithEigen=true`
"""
function newton(br::AbstractBranchResult, ind_bif::Int64; normN = norm, options = br.contparams.newtonOptions, startWithEigen = false, lens2::Lens = (@lens _), kwargs...)
	@assert length(br.specialpoint) > 0 "The branch does not contain bifurcation points"
	if br.specialpoint[ind_bif].type == :hopf
		return newtonHopf(br, ind_bif; normN = normN, options = options, startWithEigen = startWithEigen, kwargs...)
	elseif br.specialpoint[ind_bif].type == :bt
		return newtonBT(br, ind_bif; lens2 = lens2, normN = normN, options = options, startWithEigen = startWithEigen, kwargs...)
	else
		return newtonFold(br, ind_bif; normN = normN, options = options, startWithEigen = startWithEigen, kwargs...)
	end
end
################################################################################
"""
$(SIGNATURES)

Codimension 2 continuation of Fold / Hopf points. This function turns an initial guess for a Fold/Hopf point into a curve of Fold/Hopf points based on a Minimally Augmented formulation. The arguments are as follows
- `br` results returned after a call to [continuation](@ref Library-Continuation)
- `ind_bif` bifurcation index in `br`
- `lens2` second parameter used for the continuation, the first one is the one used to compute `br`, e.g. `getLens(br)`
- `options_cont = br.contparams` arguments to be passed to the regular [continuation](@ref Library-Continuation)

# Optional arguments:
- `bdlinsolver` bordered linear solver for the constraint equation
- `updateMinAugEveryStep` update vectors `a,b` in Minimally Formulation every `updateMinAugEveryStep` steps
- `startWithEigen = false` whether to start the Minimally Augmented problem with information from eigen elements
- `detectCodim2Bifurcation ∈ {0,1,2}` whether to detect Bogdanov-Takens, Bautin and Cusp. If equals `1` non precise detection is used. If equals `2`, a bisection method is used to locate the bifurcations.
- `kwargs` keywords arguments to be passed to the regular [continuation](@ref Library-Continuation)

where the parameters are as above except that you have to pass the branch `br` from the result of a call to `continuation` with detection of bifurcations enabled and `index` is the index of Hopf point in `br` you want to refine.

!!! tip "ODE problems"
    For ODE problems, it is more efficient to pass the Bordered Linear Solver using the option `bdlinsolver = MatrixBLS()`

!!! tip "startWithEigen"
    It is recommanded that you use the option `startWithEigen = true`
"""
function continuation(br::AbstractBranchResult,
					ind_bif::Int64,
					lens2::Lens,
					options_cont::ContinuationPar = br.contparams ;
					startWithEigen = false,
					detectCodim2Bifurcation::Int = 0,
					kwargs...)
	@assert length(br.specialpoint) > 0 "The branch does not contain bifurcation points"
	# options to detect codim2 bifurcations
	computeEigenElements = options_cont.detectBifurcation > 0
	_options_cont = detectCodim2Parameters(detectCodim2Bifurcation, options_cont; kwargs...)

	if br.specialpoint[ind_bif].type == :hopf
		return continuationHopf(br.prob, br, ind_bif, lens2, _options_cont;
			startWithEigen = startWithEigen,
			computeEigenElements = computeEigenElements,
			kwargs...)
	else
		return continuationFold(br.prob, br, ind_bif, lens2, _options_cont;
			startWithEigen = startWithEigen,
			computeEigenElements = computeEigenElements,
			kwargs...)
	end
end
####################################################################################################
# branch switching at Bogdanov-Takens bifurcation point
function continuation(br::AbstractResult{Tkind, Tprob}, ind_bif::Int,
			options_cont::ContinuationPar = br.contparams;
			alg = br.alg,
			δp = nothing, ampfactor::Real = 1,
			nev = options_cont.nev,
			detectCodim2Bifurcation::Int = 0,
			Teigvec = getvectortype(br),
			scaleζ = norm,
			startWithEigen = false,
			autodiff = false,
			kwargs...) where {Tkind, Tprob <: Union{FoldMAProblem, HopfMAProblem}}

		verbose = get(kwargs, :verbosity, 0) > 0 ? true : false
		verbose && println("--> Considering bifurcation point:"); _show(stdout, br.specialpoint[ind_bif], ind_bif)

		bif_type = br.specialpoint[ind_bif].type
		@assert bif_type in (:bt, :zh, :hh) "Only branching from Bogdanov-Takens, Zero-Hopf and Hopf-Hopf (for now)"

		if bif_type == :hh
			@assert Tkind <: HopfCont
		end

		# functional
		prob_ma = br.prob.prob
		prob_vf = prob_ma.prob_vf

		# continuation parameters
		computeEigenElements = options_cont.detectBifurcation > 0
		optionsCont = detectCodim2Parameters(detectCodim2Bifurcation, options_cont; kwargs...)

		# scalar type
		Ty = eltype(Teigvec)

		# compute the normal form of the bifurcation point
		nf = getNormalForm(br, ind_bif; nev = nev, verbose = verbose, Teigvec = Teigvec, scaleζ = scaleζ, autodiff = autodiff)

		# compute predictor for point on new branch
		ds = isnothing(δp) ? optionsCont.ds : δp

		if prob_ma isa FoldProblemMinimallyAugmented || bif_type == :hh
			# define guess for the first Hopf point on the branch
			pred = predictor(nf, Val(:HopfCurve), ds)

			# new continuation parameters
			parcont = pred.hopf(ds)

			# new full parameters
			params = set(set(nf.params, nf.lens[2], parcont[2]), nf.lens[1], parcont[1])

			# guess for the Hopf point
			hopfpt = BorderedArray(nf.x0 .+ pred.x0(ds), [parcont[1], pred.ω(ds)])

			# estimates for eigenvectors for ±iω
			ζ = pred.EigenVec(ds)
			ζstar = pred.EigenVecAd(ds)

			# put back original options
			@set! optionsCont.newtonOptions.eigsolver =
								getsolver(optionsCont.newtonOptions.eigsolver)
			@set! optionsCont.newtonOptions.linsolver = prob_ma.linsolver

			branch = continuationHopf(prob_vf, alg,
					hopfpt, params,
					nf.lens...,
					ζ, ζstar,
					optionsCont;
					bdlinsolver = prob_ma.linbdsolver,
					startWithEigen = startWithEigen,
					computeEigenElements = computeEigenElements,
					kwargs...
					)
			return Branch(branch, nf)

		else
			@assert prob_ma isa HopfProblemMinimallyAugmented
			pred = predictor(nf, Val(:FoldCurve), 0.)

			# new continuation parameters
			parcont = pred.fold(ds)

			# new full parameters
			params = set(set(nf.params, nf.lens[2], parcont[2]), nf.lens[1], parcont[1])

			# guess for the fold point
			foldpt = BorderedArray(nf.x0 .+ 0 .* pred.x0(ds), parcont[1])

			# estimates for null eigenvectors
			ζ = pred.EigenVec(ds)
			ζstar = pred.EigenVecAd(ds)

			# put back original options
			@set! optionsCont.newtonOptions.eigsolver =
								getsolver(optionsCont.newtonOptions.eigsolver)
			@set! optionsCont.newtonOptions.linsolver = prob_ma.linsolver
			# @set! optionsCont.detectBifurcation = 0
			# @set! optionsCont.detectEvent = 0

			branch = continuationFold(prob_vf, alg,
					foldpt, params,
					nf.lens...,
					ζstar, ζ,
					optionsCont;
					bdlinsolver = prob_ma.linbdsolver,
					startWithEigen = startWithEigen,
					computeEigenElements = computeEigenElements,
					kwargs...
					)
			return Branch(branch, nf)
		end
end
################################################################################
"""
$(SIGNATURES)

This function uses information in the branch to detect codim 2 bifurcations like BT, ZH and Cusp.
"""
function correctBifurcation(contres::ContResult)
	if contres.prob.prob isa AbstractProblemMinimallyAugmented == false
		return contres
	end
	if contres.prob.prob isa FoldProblemMinimallyAugmented
		conversion = Dict(:bp => :bt, :hopf => :zh, :fold => :cusp, :nd => :nd, :btbp => :bt)
	elseif contres.prob.prob isa HopfProblemMinimallyAugmented
		conversion = Dict(:bp => :zh, :hopf => :hh, :fold => :nd, :nd => :nd, :ghbt => :bt, :btgh => :bt, :btbp => :bt)
	else
		throw("Error! this should not occur. Please open an issue on the website of BifurcationKit.jl")
	end
	for (ind, bp) in pairs(contres.specialpoint)
		if bp.type in keys(conversion)
			@set! contres.specialpoint[ind].type = conversion[bp.type]
		end
	end
	return contres
end
