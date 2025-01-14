function getNormalForm(prob::AbstractBifurcationProblem,
			br::ContResult{ <: PeriodicOrbitCont}, id_bif::Int ;
			nev = length(eigenvalsfrombif(br, id_bif)),
			verbose = false,
			ζs = nothing,
			lens = getLens(br),
			Teigvec = getvectortype(br),
			scaleζ = norm,
			detailed = true,
			autodiff = true)
	bifpt = br.specialpoint[id_bif]

	@assert !(bifpt.type in (:endpoint,)) "Normal form for $(bifpt.type) not implemented"

	# parameters for normal form
	kwargs_nf = (nev = nev, verbose = verbose, lens = lens, Teigvec = Teigvec, scaleζ = scaleζ)

	if bifpt.type == :pd
		return perioddoublingNormalForm(prob, br, id_bif; kwargs_nf...)
	elseif bifpt.type == :cusp
		return cuspNormalForm(prob, br, id_bif; kwargs_nf...)
	elseif bifpt.type == :bp
		return branchNormalForm(prob, br, id_bif; kwargs_nf...)
	elseif bifpt.type == :ns
		return neimarksackerNormalForm(prob, br, id_bif; kwargs_nf..., detailed = detailed, autodiff = autodiff)
	end

	@assert 1==0
end

####################################################################################################
function branchNormalForm(pbwrap,
								br,
								ind_bif::Int;
								nev = length(eigenvalsfrombif(br, ind_bif)),
								verbose = false,
								lens = getLens(br),
								Teigvec = vectortype(br),
								kwargs_nf...)
	pb = pbwrap.prob
	bifpt = br.specialpoint[ind_bif]
	bptype = bifpt.type
	par = setParam(br, bifpt.param)
	period = getPeriod(pb, bifpt.x, par)

	# let us compute the kernel
	λ = (br.eig[bifpt.idx].eigenvals[bifpt.ind_ev])
	verbose && print("├─ computing nullspace of Periodic orbit problem...")
	ζ = geteigenvector(br.contparams.newtonOptions.eigsolver, br.eig[bifpt.idx].eigenvecs, bifpt.ind_ev)
	# we normalize it by the sup norm because it could be too small/big in L2 norm
	# TODO: user defined scaleζ
	ζ ./= norm(ζ, Inf)
	verbose && println("Done!")

	# compute the full eigenvector
	floquetsolver = br.contparams.newtonOptions.eigsolver
	ζ_a = floquetsolver(Val(:ExtractEigenVector), pbwrap, bifpt.x, setParam(br, bifpt.param), real.(ζ))
	ζs = reduce(vcat, ζ_a)

	nf = nothing

	return BranchPointPeriodicOrbit(bifpt.x, period, bifpt.param, par, getLens(br), real.(ζs), nothing, nf, :none, pb)
end
####################################################################################################
function perioddoublingNormalForm(pbwrap,
								br,
								ind_bif::Int;
								nev = length(eigenvalsfrombif(br, ind_bif)),
								verbose = false,
								lens = getLens(br),
								Teigvec = vectortype(br),
								kwargs_nf...)
	pb = pbwrap.prob
	bifpt = br.specialpoint[ind_bif]
	bptype = bifpt.type
	par = setParam(br, bifpt.param)
	period = getPeriod(pb, bifpt.x, par)

	# let us compute the kernel
	λ = (br.eig[bifpt.idx].eigenvals[bifpt.ind_ev])
	verbose && print("├─ computing nullspace of Periodic orbit problem...")
	ζ = geteigenvector(br.contparams.newtonOptions.eigsolver, br.eig[bifpt.idx].eigenvecs, bifpt.ind_ev)
	# we normalize it by the sup norm because it could be too small/big in L2 norm
	# TODO: user defined scaleζ
	ζ ./= norm(ζ, Inf)
	verbose && println("Done!")

	# compute the full eigenvector
	floquetsolver = br.contparams.newtonOptions.eigsolver
	ζ_a = floquetsolver(Val(:ExtractEigenVector), pbwrap, bifpt.x, setParam(br, bifpt.param), real.(ζ))
	ζs = reduce(vcat, ζ_a)

	nf = nothing

	return PeriodDoubling(bifpt.x, period, bifpt.param, par, getLens(br), real.(ζs), nothing, nf, :none, pb)

end

function perioddoublingNormalForm(pbwrap::WrapPOColl,
								br,
								ind_bif::Int;
								nev = length(eigenvalsfrombif(br, ind_bif)),
								verbose = false,
								lens = getLens(br),
								Teigvec = vectortype(br),
								kwargs_nf...)
	# Kuznetsov, Yu. A., W. Govaerts, E. J. Doedel, and A. Dhooge. “Numerical Periodic Normalization for Codim 1 Bifurcations of Limit Cycles.” SIAM Journal on Numerical Analysis 43, no. 4 (January 2005): 1407–35. https://doi.org/10.1137/040611306.
	# on page 1243

	# first, get the bifurcation point parameters
	coll = pbwrap.prob
	N, m, Ntst = size(coll)
	@assert coll isa PeriodicOrbitOCollProblem "Something is wrong. Please open an issue on the website"
	verbose && println("#"^53*"\n--> Period-Doubling normal form computation")
	bifpt = br.specialpoint[ind_bif]
	bptype = bifpt.type
	par = setParam(br, bifpt.param)
	T = getPeriod(coll, bifpt.x, par)

	F(u, p) = residual(coll.prob_vf, u, p)
	A(u,p,du) = apply(jacobian(coll.prob_vf, u, p), du)
	R2(u,p,du1,du2) = d2F(coll.prob_vf, u,p,du1,du2)
	R3(u,p,du1,du2,du3) = d3F(coll.prob_vf, u,p,du1,du2,du3)

	# we first try to get the floquet eigenvectors for μ = -1
	jac = jacobian(pbwrap, bifpt.x, par)
	# remove borders
	J = jac.jacpb
	nj = size(J, 1)
	J[end, :] .= rand(nj)
	J[:, end] .= rand(nj)
	# enforce PD boundary condition
	J[end-N:end-1, 1:N] .= I(N)
	rhs = zeros(nj); rhs[end] = 1
	q = J  \ rhs; q = q[1:end-1]; q ./= norm(q)
	p = J' \ rhs; p = p[1:end-1]; p ./= norm(p)

	J[end, 1:end-1] .= q
	J[1:end-1, end] .= p

	wext = J' \ rhs
	vext = J  \ rhs

	v₁ = @view vext[1:end-1]
	v₁★ = @view wext[1:end-1]

	ζₛ = getTimeSlices(coll, vext)
	vext ./= sqrt(∫(coll, ζₛ, ζₛ, 1))

	ζ★ₛ = getTimeSlices(coll, wext)
	v₁★ ./= 2∫(coll, ζ★ₛ, ζₛ, 1)

	v₁ₛ = getTimeSlices(coll, vcat(v₁,0))
	v₁★ₛ = getTimeSlices(coll, vcat(v₁★,0))


	return PeriodDoubling(bifpt.x, T, bifpt.param, par, getLens(br), v₁, v₁★, nf, :none, coll)

end
####################################################################################################
function predictor(nf::PeriodDoubling{ <: PeriodicOrbitTrapProblem}, δp, ampfactor)
	pb = nf.prob

	M, N = size(pb)
	orbitguess0 = nf.po[1:end-1]
	orbitguess0c = getTimeSlices(pb, nf.po)
	ζc = reshape(nf.ζ, N, M)
	orbitguess_c = orbitguess0c .+ ampfactor .*  ζc
	orbitguess_c = hcat(orbitguess_c, orbitguess0c .- ampfactor .*  ζc)
	orbitguess = vec(orbitguess_c[:,1:2:end])
	# we append twice the period
	orbitguess = vcat(orbitguess, 2nf.T)
	return (orbitguess = orbitguess, pnew = nf.p + δp, prob = pb)
end

function predictor(nf::BranchPointPeriodicOrbit{ <: PeriodicOrbitTrapProblem}, δp, ampfactor)
	orbitguess = copy(nf.po)
	orbitguess[1:end-1] .+= ampfactor .*  nf.ζ
	return (orbitguess = orbitguess, pnew = nf.p + δp, prob = nf.prob)
end
####################################################################################################
function predictor(nf::PeriodDoubling{ <: PeriodicOrbitOCollProblem}, δp, ampfactor)
	pbnew = deepcopy(nf.prob)
	N, m, Ntst = size(nf.prob)

	# we update the problem by doubling the Ntst
	pbnew = setCollocationSize(pbnew, 2Ntst, m)

	orbitguess0 = nf.po[1:end-1]

	orbitguess_c = orbitguess0 .+ ampfactor .*  nf.ζ
	orbitguess = vcat(orbitguess_c[1:end-N], orbitguess0 .- ampfactor .*  nf.ζ)

	pbnew.xπ .= orbitguess
	pbnew.ϕ .= circshift(orbitguess, length(orbitguess)÷1)

	# we append twice the period
	orbitguess = vcat(orbitguess, 2nf.T)

	# no need to change pbnew.cache
	return (orbitguess = orbitguess, pnew = nf.p + δp, prob = pbnew)
end
####################################################################################################
function predictor(nf::PeriodDoubling{ <: ShootingProblem}, δp, ampfactor)
	pbnew = deepcopy(nf.prob)
	ζs = nf.ζ
	orbitguess = copy(nf.po)[1:end-1] .+ ampfactor .* ζs
	orbitguess = vcat(orbitguess, copy(nf.po)[1:end-1] .- ampfactor .* ζs, nf.po[end])

	@set! pbnew.M = 2nf.prob.M
	@set! pbnew.ds = _duplicate(pbnew.ds) ./ 2
	orbitguess[end] *= 2
	# plot(cumsum(pb.ds) .* orbitguess[end], reshape(orbitguess[1:end-1],3, pb.M)', marker = :d) |> display
	return (orbitguess = orbitguess, pnew = nf.p + δp, prob = pbnew)
end

function predictor(nf::BranchPointPeriodicOrbit{ <: ShootingProblem}, δp, ampfactor)
	ζs = nf.ζ
	orbitguess = copy(nf.po)
	orbitguess[1:length(ζs)] .+= ampfactor .* ζs
	return (orbitguess = orbitguess, pnew = nf.p + δp, prob = nf.prob)
end
####################################################################################################
function predictor(nf::PeriodDoubling{ <: PoincareShootingProblem}, δp, ampfactor)
	pbnew = deepcopy(nf.prob)
	ζs = nf.ζ

	@set! pbnew.section = _duplicate(pbnew.section)
	@set! pbnew.M = pbnew.section.M
	orbitguess = copy(nf.po) .+ ampfactor .* ζs
	orbitguess = vcat(orbitguess, orbitguess .- ampfactor .* ζs)

	return (orbitguess = orbitguess, pnew = nf.p + δp, prob = pbnew)
end

function predictor(nf::BranchPointPeriodicOrbit{ <: PoincareShootingProblem}, δp, ampfactor)
	ζs = nf.ζ
	orbitguess = copy(nf.po)
	orbitguess .+= ampfactor .* ζs
	return (orbitguess = orbitguess, pnew = nf.p + δp, prob = nf.prob)
end
