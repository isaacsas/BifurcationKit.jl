# BifurcationKit.jl

| **Documentation** | **Build Status** | **Downloads** |
|:-----------------:|:----------------:|:-------------:|
| [![docs-stable][docs-stable-img]][docs-stable-url] [![docs-dev][docs-dev-img]][docs-dev-url] | [![Build status](https://github.com/rveltz/BifurcationKit.jl/workflows/CI/badge.svg)](https://github.com/rveltz/BifurcationKit.jl/actions) [![codecov](https://codecov.io/gh/bifurcationkit/BifurcationKit.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/bifurcationkit/BifurcationKit.jl) | [![](https://shields.io/endpoint?url=https://pkgs.genieframework.com/api/v1/badge/BifurcationKit)](https://pkgs.genieframework.com?packages=BifurcationKit)|

[docs-stable-img]: https://img.shields.io/badge/docs-stable-blue.svg
[docs-stable-url]: https://bifurcationkit.github.io/BifurcationKitDocs.jl/stable
[docs-dev-img]: https://img.shields.io/badge/docs-dev-purple.svg
[docs-dev-url]: https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev

This Julia package aims at performing **automatic bifurcation analysis** of possibly large dimensional equations F(u, λ)=0 where λ∈ℝ by taking advantage of iterative methods, dense / sparse formulation and specific hardwares (*e.g.* GPU).

It incorporates continuation algorithms (PALC, deflated continuation, ...) based on a Newton-Krylov method to correct the predictor step and a Matrix-Free/Dense/Sparse eigensolver is used to compute stability and bifurcation points.

> The idea is to be able to seemingly switch the continuation algorithm a bit like changing the time stepper (Euler, RK4,...) for ODEs.

By leveraging on the above method, it can also seek for periodic orbits of Cauchy problems. **It is by now, one of the only softwares which provides shooting methods AND methods based on finite differences or collocation to compute periodic orbits.**

The current focus is on large scale nonlinear problems and multiple hardwares. Hence, the goal is to use Matrix Free methods on **GPU** (see [PDE example](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorials2b/#The-Swift-Hohenberg-equation-on-the-GPU-(non-local)-1) and [Periodic orbit example](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorialsCGL/#Continuation-of-periodic-orbits-on-the-GPU-(Advanced)-1)) or on a **cluster** to solve non linear PDE, nonlocal problems, compute sub-manifolds...

> Despite focus on large scale problems, the package can easily handle low dimensional problems and specific optimizations are regularly added.


## Support and citation
If you use this package for your work, we ask that you cite the following paper. Open source development as part of academic research strongly depends on this. Please also consider starring this repository if you like our work, this will help us to secure funding in the future. It is referenced on HAL-Inria as follows:

```
@misc{veltz:hal-02902346,
  TITLE = {{BifurcationKit.jl}},
  AUTHOR = {Veltz, Romain},
  URL = {https://hal.archives-ouvertes.fr/hal-02902346},
  INSTITUTION = {{Inria Sophia-Antipolis}},
  YEAR = {2020},
  MONTH = Jul,
  KEYWORDS = {pseudo-arclength-continuation ; periodic-orbits ; floquet ; gpu ; bifurcation-diagram ; deflation ; newton-krylov},
  PDF = {https://hal.archives-ouvertes.fr/hal-02902346/file/354c9fb0d148262405609eed2cb7927818706f1f.tar.gz},
  HAL_ID = {hal-02902346},
  HAL_VERSION = {v1},
}
```

## Installation

This package requires Julia >= v1.3.0

To install it, please run

`] add BifurcationKit`

To install the bleeding edge version, please run

`] add BifurcationKit#master`

## Plugins

Most of the plugins are located in the organization [bifurcationkit](https://github.com/bifurcationkit):

- [DDEBifurcationKit.jl](https://github.com/bifurcationkit/DDEBifurcationKit.jl) bifurcation analysis of delay differential equations (DDE)
- [AsymptoticNumericalMethod.jl](https://github.com/bifurcationkit/AsymptoticNumericalMethod.jl) provides the numerical continuation algorithm **Asymptotic Numerical Method** (ANM) which can be used directly in `BifurcationKit.jl`
- [GridapBifurcationKit.jl](https://github.com/bifurcationkit/GridapBifurcationKit) bifurcation analysis of PDEs solved with the Finite Elements Method (FEM) using the package [Gridap.jl](https://github.com/gridap/Gridap.jl).
- [PeriodicSchurBifurcationKit.jl](https://github.com/bifurcationkit/PeriodicSchurBifurcationKit.jl) state of the art computation of Floquet coefficients, useful for computing the stability of periodic orbits.

## Examples of bifurcation diagrams


| ![](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/BDSH1d.png)   |  ![](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/mittlemannBD-1.png) |
|:-------------:|:-------------:|
| [Automatic Bif. Diagram in 1D Swift Hohenberg](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/Swift-Hohenberg1d/#d-Swift-Hohenberg-equation-(Automatic)) |  [Automatic Bif. Diagram in 2D Bratu](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/mittelmannAuto/#Automatic-diagram-of-2d-Bratu–Gelfand-problem-(Intermediate)) |
| ![](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/sh2dbranches.png)   |  ![](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/bru-po-cont-3br.png) |
| [Snaking in 2D Swift Hohenberg](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorials2/#d-Swift-Hohenberg-equation:-snaking,-Finite-Differences) |  [Periodic orbits in 1D Brusselator](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorials3/#d-Brusselator-(automatic))
| ![](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/br_pd3.png) |![](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/cgl-sh-br.png) |
| [Period doubling BVAM Model](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorialsPD/#Period-doubling-in-the-Barrio-Varea-Aragon-Maini-model)  |  [Periodic orbits in 2D Ginzburg-Landau](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorialsCGL/#d-Ginzburg-Landau-equation-(finite-differences))  |
| ![](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/carrier.png) | ![](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/GPU-branch.png) |
| [Deflated Continuation in Carrier problem](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorialCarrier/#Deflated-Continuation-in-the-Carrier-Problem)  |  [2D Swift Hohenberg on GPU](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorials2b/#d-Swift-Hohenberg-equation-(non-local)-on-the-GPU,-periodic-BC-(Advanced))  |


## Main features

- Newton-Krylov solver with generic linear / eigen *preconditioned* solver. Idem for the arc-length continuation.
- Newton-Krylov solver with nonlinear deflation and preconditioner. It can be used for branch switching for example.
- Continuation written as an [iterator](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/iterator/)
- Monitoring user functions along curves computed by continuation, see [events](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/EventCallback/)
- Continuation methods: PALC, Moore Penrose, Deflated continuation, ANM, ...
- Bifurcation points located with a bisection algorithm
- Detection of Branch, Fold, Hopf bifurcation point of stationary solutions and computation of their normal form.
- Automatic branch switching at branch points (whatever the dimension of the kernel)
- Automatic branch switching at simple Hopf points to periodic orbits
- **Automatic computation of bifurcation diagrams of equilibria**
- Fold / Hopf continuation based on Minimally Augmented formulation, with Matrix Free / Sparse Jacobian.
- Detection of all codim 2 bifurcations of equilibria and computation of the normal forms of Bogdanov-Takens, Bautin and Cusp
- Branching from Bogdanov-Takens / Zero-Hopf / Hopf-Hopf points to Fold / Hopf curve
- Periodic orbit computation and continuation using Shooting, Finite Differences or Orthogonal Collocation.
- Detection of Branch, Fold, Neimark-Sacker, Period Doubling bifurcation point of periodic orbits.
- Continuation of Fold of periodic orbits

Custom state means, we can use something else than `AbstractArray`, for example your own `struct`.

**Note that you can combine most solvers, like use Deflation for Periodic orbit computation or Fold of periodic orbits family.**


|Features|Matrix Free|Custom state| [Tutorial](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorials/) | GPU |
|---|---|---|---|---|
| (Deflated) Krylov-Newton| Yes| Yes| All| :heavy_check_mark:|
| Continuation PALC (Natural, Secant, Tangent, Polynomial) | Yes| Yes| All |:heavy_check_mark:  |
| Deflated Continuation | Yes| Yes| [:arrow_heading_up:](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorialCarrier/#Deflated-Continuation-in-the-Carrier-Problem-1) |:heavy_check_mark:  |
| Bifurcation / Fold / Hopf point detection | Yes| Yes| All / All / [:arrow_heading_up:](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorials/#Bifurcation-diagrams-with-periodic-orbits-1) | :heavy_check_mark: |
| Fold Point continuation | Yes| Yes| [:arrow_heading_up:](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorials1/#Temperature-model-(simplest-example-for-equilibria)-1), [:arrow_heading_up:](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorialsCGL/#Complex-Ginzburg-Landau-2d-1) | :heavy_check_mark: |
| Hopf Point continuation | Yes| `AbstractArray` |
| Bogdanov-Takens Point newton | Yes| `AbstractArray` |
| Branch point / Fold / Hopf normal form | Yes| Yes|  | :heavy_check_mark: | [:arrow_heading_up:](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorials3/#Continuation-of-Hopf-points-1) | |
| Branch switching at Branch / Hopf points | Yes| `AbstractArray` | [:arrow_heading_up:](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorials/#Bifurcation-diagrams-with-periodic-orbits-1) | :heavy_check_mark: |
| <span style="color:red">**Automatic bifurcation diagram computation of equilibria**</span> | Yes| `AbstractArray` |  [:arrow_heading_up:](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorials/#Automatic-bifurcation-diagram-1) | |
| Periodic Orbit (Trapezoid) Newton / continuation | Yes| `AbstractVector` | [:arrow_heading_up:](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorials3/#Brusselator-1d-(automatic)-1), [:arrow_heading_up:](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorialsCGL/#Complex-Ginzburg-Landau-2d-1) | :heavy_check_mark:|
| Periodic Orbit (Collocation) Newton / continuation | Yes| `AbstractVector` | [:arrow_heading_up:](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/ode/tutorialsODE/#Neural-mass-equation-(Hopf-aBS)) | |
| Periodic Orbit (Parallel Poincaré / Standard Shooting) Newton / continuation | Yes| `AbstractArray` |  [:arrow_heading_up:](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorials/#Bifurcation-diagrams-with-periodic-orbits-1) | |
| Fold, Neimark-Sacker, Period doubling detection | Yes| `AbstractVector` | [:arrow_heading_up:](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorials/#Bifurcation-diagrams-with-periodic-orbits-1)  | |
| Continuation of Fold of periodic orbits | Yes| `AbstractVector` | [:arrow_heading_up:](https://bifurcationkit.github.io/BifurcationKitDocs.jl/dev/tutorials/tutorialsCGL/#Complex-Ginzburg-Landau-2d-1) | :heavy_check_mark: |
| Bogdanov-Takens / Bautin / Cusp / Zero-Hopf / Hopf-Hopf point detection | Yes| Yes|  | :heavy_check_mark: |
| Bogdanov-Takens / Bautin / Cusp normal forms | Yes| Yes|  | :heavy_check_mark: |
| Branching from Bogdanov-Takens / Zero-Hopf / Hopf-Hopf to Fold / Hopf curve | Yes | `AbstractVector` | |  |
