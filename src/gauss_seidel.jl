##############################################################################
##
## Solution method: coordinate gradient descent 
## (also called alternative regressions, Gauss Seidel)
##
##############################################################################

##############################################################################
##
## Factor Model (no regressors)
##
##############################################################################

function fit!(::Type{Val{:gauss_seidel}}, 
    fp::FactorModel,
    fs::FactorSolution;
    maxiter::Integer  = 100_000,
    tol::Real = 1e-9,
    lambda::Real = 0.0
    )
    lambda == 0.0 || error("The alternative regression method only works with lambda = 0.0")

    # initialize
    iterations = fill(maxiter, rank(fp))
    converged = fill(false, rank(fp))
    iter = 0
    res = deepcopy(fp.y)
    fp = FactorModel(res, fp.sqrtw, fp.idrefs, fp.timerefs, rank(fp))
    idscale = Array(Float64, size(fs.idpool, 1))
    timescale = Array(Float64, size(fs.timepool, 1))

    for r in 1:rank(fp)
        fsr = slice(fs, :, r)
        oldf_x = ssr(fp, fsr)
        iter = 0
        while iter < maxiter
            iter += 1
            update!(Val{:gauss_seidel}, res, fp.sqrtw, fp.idrefs, fp.timerefs, fsr.idpool, 
                idscale, fsr.timepool)
            update!(Val{:gauss_seidel}, res, fp.sqrtw, fp.timerefs, fp.idrefs, fsr.timepool, 
                timescale, fsr.idpool)
            f_x = ssr(fp, fsr)
            if abs(f_x - oldf_x) < (abs(f_x) + tol) * tol
                iterations[r] = iter
                converged[r] = true
                break
            else
                oldf_x = f_x
            end
        end
        if r < rank(fp)
            rescale!(fsr)
            subtract_factor!(res, fp, fsr)
        end
    end
    return rescale(fs), maximum(iterations), all(converged)
end

##############################################################################
##
## Interactive FixedEffectModel
##
##############################################################################

function fit!(::Type{Val{:gauss_seidel}},
    fp::InteractiveFixedEffectsModel,
    fs::InteractiveFixedEffectsSolution; 
    maxiter::Integer = 100_000, 
    tol::Real = 1e-9,
    lambda::Real = 0.0)
    lambda == 0.0 || error("The alternative regression method only works with lambda = 0.0")

    #qr fact factorization cannot divide in place for now
    crossx = cholfact!(At_mul_B(fp.X, fp.X))
    M = crossx \ fp.X'

    N = size(fs.idpool, 1)
    T = size(fs.timepool, 1)

    res = deepcopy(fp.y)

    idscale = Array(Float64, size(fs.idpool, 1))
    timescale = Array(Float64, size(fs.timepool, 1))

    # starts loop
    converged = false
    iterations = maxiter
    iter = 0
    f_x = Inf
    oldf_x = Inf
    while iter < maxiter
        iter += 1
        (f_x, oldf_x) = (oldf_x, f_x)

        # Given beta, compute incrementally an approximate factor model
        copy!(res, fp.y)
        BLAS.gemm!('N', 'N', -1.0, fp.X, fs.b, 1.0, res)
        for r in 1:rank(fp)
            fsr = slice(fs, :, r)
            update!(Val{:gauss_seidel}, res, fp.sqrtw, fp.idrefs, fp.timerefs, fsr.idpool, idscale, fsr.timepool)
            update!(Val{:gauss_seidel}, res, fp.sqrtw, fp.timerefs, fp.idrefs, fsr.timepool, timescale, fsr.idpool)
            subtract_factor!(res, fp, fsr)
        end

        # Given factor model, compute beta
        copy!(res, fp.y)
        subtract_factor!(res, fp, fs)
        ## corresponds to Gauss Niedel with acceleration
        scale!(fs.b, -0.5)
        BLAS.gemm!('N', 'N', 1.5, M, res, 1.0, fs.b)

        # Check convergence
        BLAS.gemm!('N', 'N', -1.0, fp.X, fs.b, 1.0, res)
        f_x = sumabs2(res)
        if abs(f_x - oldf_x) < (abs(f_x) + tol) * tol
            converged = true
            iterations = iter
            break
        end
    end
    return rescale(fs), iterations, converged
end

##############################################################################
##
## update! by alternative regressions
##
##############################################################################

function update!{R1, R2}(::Type{Val{:gauss_seidel}},
    y::Vector{Float64},
    sqrtw::AbstractVector{Float64},
    p1refs::Vector{R1},
    p2refs::Vector{R2},
    p1::AbstractVector{Float64},
    p1scale::Vector{Float64},
    p2::AbstractVector{Float64}
    )
    fill!(p1, zero(Float64))
    fill!(p1scale, zero(Float64))
    @inbounds @simd for i in 1:length(y)
        p1i = p1refs[i]
        xi = sqrtw[i] * p2[p2refs[i]] 
        p1[p1i] += xi * y[i]
        p1scale[p1i] += abs2(xi)
    end
    @inbounds @simd for i in 1:length(p1)
        s = p1scale[i]
        if s > 0
            p1[i] /= s
        end
    end
end