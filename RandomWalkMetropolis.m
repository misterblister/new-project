(* :Title: RandomWalkMetropolis` *)

(* :Author: Mark Fisher *)

(* :Date: July 2007 *)

(* :Mathematica Version: 6 *)

(* :Package Version: 2.0
	Modified for Version 6.0 June 2007. Completely revamped.
*)

(* :Summary:
This package implements the (random-walk) Metropolis version of the Markov
Chain Monte Carlo (MCMC) algorithm. MCMC algorithms are used to draw from
probability distributions. The function BridgeEstimate can be used to
compute the normalizing constant.
*)

(* :Discussion:
The Markov Chain is implemented via NestList. The "state" vector is the
parameter vector with its value appended, {x__, v_}. The iteration function
generates a proposal and returns the proposal (with its value) if its value is
greater than a random fraction of the current value. Otherwise the current state
is returned. Proposals are generated by random-walk Gaussian or T-distributions.

The first argument to RandomWalkMetropolis is the function that returns the
value of the parameter vector. In order to be compiled, it must be a
function of a single vector argument and it must have the head Function.
For example, the function Function[{x, y}, x * y] will not work because it
take two arguments. Depending upon the interpretation of the arguments x
and y, there are a number of ways to produce an acceptable function. First,
if x and y are both scalars, then Function[z, z[[1]] * z[[2]]] works. For
more complicated expressions, it may be convenient to do something along
the following lines: Function[z, With[{x = z[[1]], y = z[[2]]}, x * y]].
Second, if x is a scalar and y is a vector, then Function[z, With[{x =
First[z], y = Rest[z]}, x * y]] works. In this way, complicated expressions
that involve symbols with mixed tensor ranks can be embedded in a function
that will work properly with RandomWalkMetropolis.

In some cases, it is better not to compile the function. In this case, one
can use the following example as a template. Define

g[x_?(VectorQ[#, NumericQ]&)] := ...

and use the option CompilePatterns -> {{g[_], _Real, 0}}.

This package also includes functions for computing the marginal likelihood
of the data in a number of ways. The best method is computed via the bridge
estimator (BridgeEstimate). Other methods include Geweke's implementation
of Gelfand and Day's modified harmonic mean (MHMEstimate), Muller's method
(MarginalLikelihoodMuller), and the method of Chib and Jeliazkov
(MarginalLikelihoodCJ).

In addition the package implements Geweke's separated partial means test
for convergence of an MCMC chain.
*)

(* :References:
	RandomWalkMetropolis implements Agorithm A.29 (p. 288) in
	Robert, Christian P. and George Casella (2004) Monte Carlo
		Statistical Methods, Second Edition, Springer.

	For the Gelfand-Dey method of marginal likelihood estimation, see
	Koop, Gary (2003) Bayesian Econometrics, John Wiley & Sons,
		pp. 104-106.
	For additional details, Koop refers the reader to
	Geweke, John (1999) Using Simulation Methods for Bayesian Econometric
		Models: Inference, Development, and Communication (with discussion
		and rejoinder), Econometric Reviews, 18, pp. 1-126.
	For the bridge estimation approach see
	Meng and Wong (1996) Simulating ratios of normalizing constants via
		a simple density: A theoretical exploration, Statistica Sinica, 6,
		pp. 831-860.
	Mira and Nicholls (2004) Bridge estimation of the probability density
	at a point, Statistica Sinica, 14, pp. 603-614.
	The method due to Ulrich K. Muller is unpublished.

	For the separated partial means test, see
	Geweke, John (2005) Contemporary Bayesian Econometrics and Statistics,
		John Wiley & Sons, pp. 149-150.
*)

BeginPackage["RandomWalkMetropolis`"]

If[$Version < 9, Needs["MultivariateStatistics`"]]

RandomWalkMetropolis::usage =
"RandomWalkMetropolis[f, start, step, nDraws, opts] or\n\
RandomWalkMetropolis[expr, {x, start}, step, nDraws, opts]\n\
returns nDraws steps of a Markov Chain Monte Carlo (MCMC) simulation \
computed via the random-walk Metropolis algorithm, \
beginning at the vector start of starting values, where step is a scalar or \
vector (with the same dimension as start) that represents standard \
deviations. Alternatively, step can be a covariance matrix. \
The function f must take a single vector argument and return \
the log of the kernel value unless the option LogLikelihood is set to False. \
In addition, f must either have the head Function (if f is to be \
compiled) or be a symbolic head that only evaluates with a numerical argument. \
Alternatively, if one supplies the expression expr, then x can be either a \
single symbolic argument or a list of arguments. In any case, if start \
is partitioned, then a \"block\" version of the Metropolis algorithm will \
be used. In this case, the step must be structured to give the appropriate \
standard deviation(s) and/or covariance for each block. \
Thinning and burn-in can be controlled with the options ThinningNumber \
and BurnInNumber. MetropolisMCMC also takes the \
options  RetainValues, InBoundsQ, RegroupOutput and CompilePatterns. \
(See the usage notes.)"

LogLikelihood::usage =
"LogLikelihood is an option for RandomWalkMetropolis that \
specifies whether the function returns values proportional to the \
likelihood or to the loglikelihood. The default setting is \
LogLikelihood -> True."

InBoundsQ::usage =
"InBoundsQ is an option for RandomWalkMetropolis \
that specifies a function that returns True of False to be applied to the \
proposal prior to evaluating the likelihood function. For example, \
InBoundsQ -> (Min[#]>=0 && Plus@@#<=1 &). The default setting is \
InBoundsQ -> (True&)."

RegroupOutput::usage =
"RegroupOutput is an option for RandomWalkMetropolis \
which specifies whether to regroup each row of the output from {x__, v_} \
to {{x}, v}. The default is RegroupOutput -> True."

RetainValues::usage =
" RetainValues is an option for RandomWalkMetropolis \
which specifies whether to discard the appended values. The default \
setting is  RetainValues -> False."

CompilePatterns::usage =
"CompilePatterns is an option for \
RandomWalkMetropolis which specifies the list of patterns supplied to \
Compile (as its third argument). These patterns specify the return types \
of external calls. The default setting is CompilePatterns -> {}."

DegreesOfFreedom::usage =
"DegreesOfFreedom is an option for \
RandomWalkMetropolis which specifies the number of degrees of freedom for \
the proposal distribution. The default setting is DegreesOfFreedom -> \
\[Infinity] which specifies the Gaussian distribution. Additional valid \
settings are any positive integer. For example, DegreesOfFreedom -> 1 \
specifies the Cauchy distribtuion (i.e., t distribtion with 1 degree of \
freedom)."

ThinningNumber::usage = "ThinningNumber is an option for \
RandomWalkMetropolis which specifies the number of draws to return \
as output. The setting ThinningNumber -> n results in every n-th draw \
being returned. The default is ThinningNumber -> 1."

BurnInNumber::usage = "BurnInNumber is an option for \
RandomWalkMetropolis which specifies the number of draws to \
discard. Setting BurnInNumber -> n results in the first n draws \
being discarded. The default is BurnInNumber -> 0."

AcceptanceRate::usage =
"AcceptanceRate[mc] computes, the fraction of times \
the proposal is accepted; namely, N[Length[Split[mc]]/Length[mc]]."

MHMFunction::usage =
"MHMFunction[mean, cov, p] returns a function that \
can be used to compute the normalization constant where mean is the \
vector of means of the MCMC parameter matrix from a \
Markov Chain Monte Carlo simulation and cov is the covariance matrix. \
The third argument p specifies \
the truncation for the Gaussian in terms of a p-value. Alternatively, one \
may specify MHMFunction[mcmc, p], where mcmc is the MCMC parameter matrix \
of parameters."

MHMEstimate::usage =
"MHMEstimate[mcmcdata, p] returns the Gelfand-Dey estimate of the \
normalization constant given the Markov Chain Monte Carlo simulation, \
where mcmcdata is produced by MetropolisMCMC with the option \
 RetainValues -> False and where the truncation point is controlled \
by the \"p-value\" p. MHMEsitmate takes the option LogLikelihood, \
which specifies whether the likelihood values are in logs. \
The default value is LogLikelihood -> False. If the option is \
specified the value for p must also be specified."

MarginalLikelihoodMuller::usage = "MarginalLikelihoodMuller[mc, fun, {m, \
V}, n (,opts)] computes the log of the marginal likelihood from the MCMC \
output mc generated from the kernel fun using n draws from a Gaussian \
weighting distribution with mean m and covariance matrix V. (The method is \
due to Ulrich K. Muller.) Since the draws from the Gaussian distribution \
are independent, n can be substantially less than the length of mc. Each \
row of mc output contains the draw and the associated kernel value. (The \
kernel values are assumed to be in logs unless the option LogLikelihood -> \
False is specified.) A function (returning True|False) that determines the \
bounds of the parameter space can be specified via the option \
InBoundsQ."

MullerFunction::usage = "MullerFunction[rf, rg][logC] is a helper function \
called by MarginalLikelihoodMuller. MullerFunction calls the compiled \
ComputeListSum."

MarginalLikelihoodCJ::usage = "MarginalLikelihoodCJ[mc, f, V, xstar, n] \
computes the log of the marginal likelihood of the data given the \
Metropolis output mc according to Chib-Jeliazkov method, where f is the \
kernel of the posterior, V is the covariance matrix of the random-walk \
Gaussian proposal density, xstar is the point at which to estimate the \
density of the poseterior, and n is the number of draws of the Gaussian \
weighting function."

BridgeEstimate::usage = "BridgeEstimate[{logf1, logf2}, {draws1, draws2}, psi] \
computes the bridge estimate of Log[c1/c2] where ci is the normalizing \
constant for the kernel Exp[fi] given the draws from the two distributions. \
The parameter psi should be set the the ratio of the number of \
\"independent\" draws in draws1 relative to the number of independent draws \
in draws2. (When in doubt, set it to 1.) BridgeEstimate[mc, fun, {m, V}, \
{n, psi}] computes the bridge estimate of the log of the marginal \
likelihood given the posterior kernel fun using the MCMC output mc; n draws \
are made from the Gaussian weighting function which is centered at m with \
covariance matrix V."

BridgeEstimatePowerFamily::usage = "BridgeEstimatePowerFamily[{z1, z2}, {k, \
A}] returns the bridge estimate of the log of the ratio of normalizing \
constants given the lists of log differences z1 and z2 and the power family \
parameters k and A."

BridgeEstimateFromMetropolis::usage = "BridgeEstimateFromMetropolis[{fun, \
start, stepsize, mcsteps}, {m, V}, {n, psi} (, opts)]."

ForceDraws::usage = "ForceDraws is an option for BridgeEstimate which \
specifies whether to enforce the number of draws from the Gaussian \
to equal the number specified. This is an issue if draws can be \
discarded as out-of-bounds. With the default setting ForceDraws -> \
True, successive draws are made until the number specified are obtained."

NumericalStandardError::usage = "NumericalStandardError[data, L] \
an estimate of the numerical standard error of the mean of the data
computed using the Newey-West method with L lags."

SeparatedPartialMeans::usage = "SeparatedPartialMeans[data, p, L] \
returns the p-value for Geweke's separated partial means test of the \
data given the number of groups p and the number of lags L."

Begin["`Private`"]

(* used in the FindRoot in BridgeEstimate *)
SetAttributes[NProtect, HoldAll]
NProtect[f_[{args__}]] := f[{args}] /; And @@ (NumericQ /@ {args})
NProtect[f_[args__]] := f[args] /; And @@ (NumericQ /@ {args})


AcceptanceRate[mc_List] := N[Length[Split[mc]]/Length[mc]]

NeweyWest[data_, L_] :=
	With[{dev = data - Mean[data], n = Length[data]},
	Prepend[Table[2 (L - s)/L, {s, 1, L}], 1].
		(NestList[PadRight[Rest[#], n] &, dev, L].dev)/n
	]

NumericalStandardError[data_, L_] := NeweyWest[data, L]/Sqrt[Length[data]]

SeparatedPartialMeans[data_, p_Integer?Positive, L_Integer?Positive] /;
		(Mod[Length[data], 2*p] == 0 && p > 1) :=
	Module[{Mp, subgroups, hvec, s2vec, band11, band12, bands, chisq},
	Mp = Length[data]/(2*p);
	subgroups = Partition[data, Mp][[2 ;; All ;; 2]];
	hvec = Differences[Mean /@ subgroups];
	s2vec = NeweyWest[#1, L] & /@ subgroups;
	band11 = 2*(MovingAverage[s2vec, 2]/Mp);
	band12 = -s2vec[[2 ;; -2]]/Mp;
	bands = DeleteCases[{Band[{1, 1}] -> band11, Band[{1, 2}] -> band12,
			Band[{2, 1}] -> band12}, Band[_] -> {}];
	chisq = hvec . Inverse[SparseArray[bands]] . hvec;
	1 - CDF[ChiSquareDistribution[p - 1], chisq]
	]

SeparatedPartialMeans[__] := $Failed

RandomWalkMetropolis::baddf = "DegreesOfFreedom must be either a positive \
integer or \[Infinity]."

RandomWalkMetropolis::badthin = "ThinningNumber must be a positive \
integer."

RandomWalkMetropolis::badburn = "BurnInNumber must be a nonnegative \
integer."

Options[RandomWalkMetropolis] = {
	LogLikelihood -> True,
	InBoundsQ -> (True&),
	RetainValues -> False,
	RegroupOutput -> True,
	DegreesOfFreedom -> \[Infinity],
	CompilePatterns -> {},
	ThinningNumber -> 1,
	BurnInNumber -> 0,
	Compiled -> True
	}

RandomWalkMetropolis[
		expr_,
		{var_Symbol, start_?(VectorQ[#, NumericQ]&)},
		stepSize_,
		nDraws_Integer?Positive,
		opts : OptionsPattern[]
		] :=
	RandomWalkMetropolis[
		Function @@ {var, expr},
		start,
		stepSize,
		nDraws,
		opts]

RandomWalkMetropolis[
		expr_,
		{vars:{__Symbol}, start_?(VectorQ[#, NumericQ]&)},
		stepSize_,
		nDraws_Integer?Positive,
		opts : OptionsPattern[]
		] :=
	Block[{z},
	RandomWalkMetropolis[
		Function @@ {z, expr /.
			Quiet[Thread[vars -> Table[z[[i]], {i, Length[vars]}]]]},
		start,
		stepSize,
		nDraws,
		opts]
		]

RandomWalkMetropolis[
		expr_,
		{var_Symbol, start:{{__} ..}},
		stepSize:{__},
		nDraws_Integer?Positive,
		opts : OptionsPattern[]
		] :=
	RandomWalkMetropolis[
		Function @@ {var, expr},
		start,
		stepSize,
		nDraws,
		opts]

RandomWalkMetropolis[
		expr_,
		{vars:{__Symbol}, start:{{__} ..}},
		stepSize:{__},
		nDraws_Integer?Positive,
		opts : OptionsPattern[]
		] :=
	Block[{z},
	RandomWalkMetropolis[
		Function @@ {z, expr /.
			Quiet[Thread[vars -> Table[z[[i]], {i, Length[vars]}]]]},
		start,
		stepSize,
		nDraws,
		opts]
		]


RandomWalkMetropolis[
		fun_,
		start_?(VectorQ[#, NumericQ]&),
		stepSize_,
		nDraws_Integer?Positive,
		OptionsPattern[]
		] :=
	Module[{log, retain, regroup, patt, df, bfun, thin, burn,
			compiled, k, chol, sfun, logfun, nfun, sv, mcfun, mc},
	{log, retain, regroup, patt, df, bfun, thin, burn, compiled} =
		OptionValue @
			{LogLikelihood, RetainValues, RegroupOutput, CompilePatterns,
				DegreesOfFreedom, InBoundsQ, ThinningNumber, BurnInNumber,
				Compiled};
	If[Not[(IntegerQ[df] && df > 0) || df === Infinity],
		Message[RandomWalkMetropolis::baddf]; Return[$Failed]];
	If[Not[IntegerQ[thin] && thin > 0],
		Message[RandomWalkMetropolis::badthin]; Return[$Failed]];
	If[Not[IntegerQ[burn] && thin >= 0],
		Message[RandomWalkMetropolis::badburn]; Return[$Failed]];
	logfun = If[TrueQ[log], fun, Log[fun[#]]&];
	k = Length[start];
	chol = AssembleCholesky[stepSize, k];
	sfun = AssembleStepFunction[chol, k, df];
	nfun = AssembleNestFunction[logfun, bfun, sfun];
	sv = Append[start, logfun[start]];

	(* all the heavy lifting next *)
	mcfun =
		If[TrueQ[compiled],
			CompileMCMCFunction[nfun, sv, nDraws, thin, burn, patt],
			AssembleMCMCFunction[nfun, sv, nDraws, thin, burn]
		];
	mc = mcfun[];
	(* structure output *)
	If[TrueQ[retain],
		(* then *)
		If[TrueQ[regroup],
			(* then regroup *)
			Through[{Most, Last}[#]] & /@ mc,
			(* else return unformatted *)
			mc
			],
		(* else return parameters only *)
		mc[[All, ;; -2]]
		]
	]

RandomWalkMetropolis[
		fun_,
		start:{{__} ..},
		stepSize:{__},
		nDraws_,
		opts : OptionsPattern[]
		] /; Length[start] === Length[stepSize] :=
	Module[{log, retain, regroup, patt, df, bfun, thin, burn, compiled,
		sfun, logfun, nfun, sv, mcfun, mc, chol, k, m, n, p},
	{log, retain, regroup, patt, df, bfun, thin, burn, compiled} =
		OptionValue @
			{LogLikelihood, RetainValues, RegroupOutput, CompilePatterns,
				DegreesOfFreedom, InBoundsQ, ThinningNumber, BurnInNumber,
				Compiled};
	If[Not[(IntegerQ[df] && df > 0) || df === Infinity],
		Message[RandomWalkMetropolis::baddf]; Return[$Failed]];
	If[Not[IntegerQ[thin] && thin > 0],
		Message[RandomWalkMetropolis::badthin]; Return[$Failed]];
	If[Not[IntegerQ[burn] && thin >= 0],
		Message[RandomWalkMetropolis::badburn]; Return[$Failed]];
	logfun = If[TrueQ[log], fun, Log[fun[#]]&];
	nfun = AssembleNestFunction[logfun, bfun];
	sv = Append[Flatten[start], logfun[Flatten[start]]];

	(* additional stuff for blocks *)
	k = Length /@ start;
	m = Length[k];
	n = Total[k];
	p = FoldList[Plus, 1, Most[k]];
	chol = MapThread[AssembleCholesky, {stepSize, k}];
	dist = If[df === Infinity, NormalDistribution[], StudentTDistribution[df]];
	$index = 0;
	$step = With[{k = k, m = m, n = n, p = p, chol = chol, dist = dist},
		Function[{},
			$index = Mod[$index+1, m, 1];
			RotateRight[
				Join[
					RandomReal[dist, k[[$index]]].chol[[$index]],
					Table[0., {n - k[[$index]]}]
					],
				p[[$index]] - 1]]
				];
	thin = m * thin;
	burn = m * burn;
	patt = Join[patt, {{HoldPattern[$step[]], _Real, 1}}];

	(* all the heavy lifting next *)
	mcfun =
		If[TrueQ[compiled],
			CompileMCMCFunction[nfun, sv, nDraws, thin, burn, patt],
			AssembleMCMCFunction[nfun, sv, nDraws, thin, burn]
		];
	mc = mcfun[];
	(* structure output *)
	If[TrueQ[retain],
		(* then *)
		If[TrueQ[regroup],
			(* then regroup *)
			Through[{Most, Last}[#]] & /@ mc,
			(* else return unformatted *)
			mc
			],
		(* else return parameters only *)
		mc[[All, ;; -2]]
		]
	]

RandomWalkMetropolis[__] := $Failed

AssembleCholesky[stepSize_, k_] :=
	CholeskyDecomposition[
		Switch[
			TensorRank[stepSize],
			0, stepSize^2 * IdentityMatrix[k],
			1, DiagonalMatrix[stepSize^2],
			2, (Transpose[#] + #)/2& @ stepSize (* covariance matrix *)
			]]

AssembleStepFunction[chol_, k_, df_] :=
	Switch[df,
		Infinity, (* normal proposal *)
			Function[{},
			Table[Sqrt[-2 Log[RandomReal[]]] Cos[2 Pi RandomReal[]], {k}].chol
			],
		_, 				(* t proposal *)
			Function[{},
			(1/Sqrt[(#.#)&[
					Table[Sqrt[-2 Log[RandomReal[]]] Cos[2 Pi RandomReal[]], {df}]]/df] *
			Table[Sqrt[-2 Log[RandomReal[]]] Cos[2 Pi RandomReal[]], {k}]).chol
			]
		]

AssembleNestFunction[vfun_, bfun_, step_] :=
		Function[s,
			Module[{p, pval},
			p = Most[s] + step[];
			If[bfun[p],
				pval = vfun[p];
				If[pval - Last[s] >= Log[RandomReal[]],
					Append[p, pval],
					s],
				s]
		]]

(* version for blocks *)
AssembleNestFunction[vfun_, bfun_] :=
		Function[s,
			Module[{p, pval},
			p = Most[s] + $step[];
			If[bfun[p],
				pval = vfun[p];
				If[pval - Last[s] >= Log[RandomReal[]],
					Append[p, pval],
					s],
				s]
		]]

AssembleMCMCFunction[nfun_, start_, nDraws_, nThin_, nBurn_] :=
	Function[{}, (* no args *)
	Rest @
		NestList[
			Nest[nfun, #, nThin]&,
			Nest[nfun, start, nBurn],
			nDraws]
		]

CompileMCMCFunction[nfun_, start_, nDraws_, nThin_, nBurn_, patt_] :=
	Compile[{}, (* no args *)
	Rest @
		NestList[
			Nest[nfun, #, nThin]&,
			Nest[nfun, start, nBurn],
			nDraws],
		patt]


(***** BridgeEstimate *****)

BridgeEstimate::badbounds = "The interval `1` does not contain zero. \
Returning the value closest to zero. Try using a larger number of draws \
from the weighting distribution."

BridgeEstimate::nodraws = "There are no draws from test distribution in \
bounds."

BridgeEstimate::ndraws = "There are `1` draws from test distribution in \
bounds."

Options[BridgeEstimate] = {
	InBoundsQ -> (True &),
	LogLikelihood -> True,
	ForceDraws -> True
	}

BridgeEstimate[
		mc_,
		fun_,
		{m_List, V_List},
		{n_Integer, psi_?NumericQ},
		opts:OptionsPattern[]
		] /;
		(Dimensions[mc][[-1]] == 2 &&
		MatrixQ[mc[[All, 1]], NumericQ] &&
		VectorQ[mc[[All, 2]], NumericQ]) :=
	Module[{bfun, loglike, force, k, t, ran, logf, logg,
		fOnMC, gOnMC, fOnRan, gOnRan, z1, z2},
	{bfun, loglike, force} =
		OptionValue @ {InBoundsQ, LogLikelihood, ForceDraws};
	If[TrueQ[force],
		(* then *)
		ran = Table[
			While[
				t = RandomReal[MultinormalDistribution[m, V]];
				!bfun[t]];
			t,
		{n}],
		(* else *)
		ran = Select[RandomReal[MultinormalDistribution[m, V], n], bfun[#]&];
		If[Length[ran] == 0, Message[BridgeEstimate::nodraws]; Return[$Failed]];
		Message[BridgeEstimate::ndraws, Length[ran]];
		];
	logf = If[TrueQ[loglike], fun, Log[fun[#]] &];
	k = Length[m];
	logg = With[{S = Inverse[V], const = -Log[(2Pi)^(k/2)Sqrt[Det[V]]]},
  		Compile[{{z, _Real, 1}}, const - (z - m).S.(z - m)/2]
  		];
	fOnMC = If[loglike, mc[[All, 2]], Log[mc[[All, 2]]]];
	gOnMC = logg /@ mc[[All, 1]];
	fOnRan = If[bfun @ #, logf @ #, -$MaxMachineNumber] & /@ ran;
	gOnRan = logg /@ ran;
	z1 = fOnMC - gOnMC;
	z2 = gOnRan - fOnRan;
	BridgeEstimate[{z1, z2}, psi, opts]
	]

BridgeEstimate[{f1_, f2_}, {draws1_List, draws2_List}, psi_?NumericQ,
		opts:OptionsPattern[]] :=
	With[{
		z1 = (f1[#] - f2[#])& /@ draws1,
		z2 = (f2[#] - f1[#])& /@ draws2
		},
	BridgeEstimate[{z1, z2}, psi, opts]
		]

BridgeEstimate[{z1_List, z2_List}, psi_?NumericQ, opts:OptionsPattern[]] :=
	With[{fun = CompileBridgeFunction[{z1, z2}, psi]},
	Block[{x},
		-x /. FindRoot[
			NProtect[fun[x]], (* NProtect defined above *)
			{x, LogRatioStartingValue[{z1, z2}]},
			FilterRules[{opts}, Options[FindRoot]] // Evaluate]
		]]

CompileBridgeFunction[{z1_, z2_}, psi_] :=
	With[{
		max = Log[$MaxMachineNumber], (* trap for non machine precsion numbers *)
		n1 = Length[z1], n2 = Length[z2]},
	Compile[{x},
		(Plus @@ (If[# < max, 1/(psi + Exp[#]), 0]& /@ (z2 - x)))/n2 -
		(Plus @@ (If[# < max, 1/(1 + psi * Exp[#]), 0]& /@ (z1 + x)))/n1
	]]

(* provide starting value for FindRoot *)
LogRatioStartingValue[{z1_, z2_}] :=
	BridgeEstimatePowerFamily[{z1, z2}, {1, 1}]

BridgeEstimatePowerFamily[{z1_, z2_}, {k_, A_}] :=
	With[{t = A^(1/k)},
	Log[Mean[(t + Exp[#/k])^(-k)& /@ z1]/
		Mean[(1 + t * Exp[#/k])^(-k)& /@ z2]]
	]

BridgeEstimateFromMetropolis[
		{fun_, start_, stepsize_, mcsteps_},
		{m_, V_}, {n_, psi_}, opts:OptionsPattern[]] :=
	Module[{mc},
	mc = RandomWalkMetropolis[fun, start, stepsize, mcsteps, opts,
		LogLikelihood -> True,  RetainValues -> False];
	BridgeEstimate[mc, fun, {m, V}, {n, psi}, opts, LogLikelihood -> True]
	]

(* Modified Harnomonic Mean (a.k.a. Gelfand-Dey) *)

MHMEstimate[mc_, p_:(.01)] /;
			(Dimensions[mc][[-1]] == 2 &&
			MatrixQ[mc[[All, 1]], NumericQ] &&		(* parameters *)
			VectorQ[mc[[All, 2]], NumericQ]) :=		(* values *)
	1/Mean[
		(MHMFunction[mc[[All, 1]], p] /@ mc[[All, 1]])/mc[[All, 2]]
		]

Options[MHMEstimate] = {LogLikelihood -> False}

MHMEstimate[mc_, p_:(.01), OptionsPattern[]] /;
			(Dimensions[mc][[-1]] == 2 &&
			MatrixQ[mc[[All, 1]], NumericQ] &&		(* parameters *)
			VectorQ[mc[[All, 2]], NumericQ]) :=		(* values *)
	With[{vals = If[
		TrueQ[OptionValue[LogLikelihood]],
		Exp[mc[[All, 2]]],
		mc[[All, 2]]]},
	1/Mean[
		(MHMFunction[mc[[All, 1]], p] /@ mc[[All, 1]])/vals
		]
	]

MHMFunction[mc_?(MatrixQ[#, NumericQ]&), p_:(.01)] :=
	MakeMHMFunction[##, p]& @@ MCMeanAndCovariance[mc]

MHMFunction[___] := $Failed

MHMEstimate[___] := $Failed

MCMeanAndCovariance[mc_?(MatrixQ[#, NumericQ]&)] :=
	{First[#], Rest[#]}& @ MCMeanCov[mc]

MCMeanAndCovariance[mc_?(MatrixQ[#, NumericQ]&)] := 
	With[{cov = Covariance[mc], n = Length[mc]},
	{Mean[mc], .5((n - 1)/n)(cov+Transpose[cov])}
	]

MCMeanCov = Compile[{{mc, _Real, 2}},
	Module[{
		len = Length[mc],
		data = Transpose[mc],
		mean = {1.},
		centered = {{1.}},
		cov = {{1.}}
		},
	mean = (Plus @@@ data)/len;
	centered = data - mean;
	cov = (centered.Transpose[centered])/len;
	cov = (cov + Transpose[cov])/2;
	Prepend[cov, mean]
	]];

MakeMHMFunction[mean_, cov_, p_:(.01)] :=
	With[{
		n = Length[mean],
		inv = Inverse[cov]
		},
	With[{
		const = N @ 1/(Sqrt[(2*Pi)^n * Det[cov]] * (1-p)),
		invGamma = N @ 2*InverseGammaRegularized[n/2, 0, 1 - p]
		},
	Compile[{{vec, _Real, 1}},
		With[{
			quad = (mean - vec).inv.(mean - vec)
			},
		If[quad <= invGamma, Exp[-quad/2]const, 0]
	]]]]

(***** MarginalLikelihoodMuller *****)
(* Ulrich K. Muller's method for computing the constant of integration *)

MarginalLikelihoodMuller::badbounds = "The interval `1` does not contain \
zero. Returning the value closest to zero. Try using a larger number of \
draws from the weighting distribution."

Options[MarginalLikelihoodMuller] =
	{InBoundsQ -> (True &), LogLikelihood -> True}

MarginalLikelihoodMuller[mc_, fun_, {m_, V_}, n_Integer,
			opts:OptionsPattern[]] /;
		(Dimensions[mc][[-1]] == 2 &&
		MatrixQ[mc[[All, 1]], NumericQ] &&
		VectorQ[mc[[All, 2]], NumericQ]) :=
	Module[{fropts, bfun, loglike, k, ran, logf, logg,
		fOnMC, gOnMC, fOnRan, gOnRan, rf, rg, lo, hi, mlo, mhi, cf},
	{bfun, loglike} = OptionValue @ {InBoundsQ, LogLikelihood};
	k = Length[m];
	ran = RandomReal[MultinormalDistribution[m, V], n];
	logf = If[TrueQ[loglike], fun, Log[fun[#]] &];
	logg = With[{S = Inverse[V], const = -Log[(2Pi)^(k/2)Sqrt[Det[V]]]},
  		Compile[{{z, _Real, 1}}, const - (z - m).S.(z - m)/2]
  		];
	fOnMC = If[TrueQ[loglike], mc[[All, 2]], Log[mc[[All, 2]]]];
	gOnMC = logg /@ mc[[All, 1]];
	fOnRan = If[bfun @ #, logf @ #, -$MaxMachineNumber] & /@ ran;
	gOnRan = logg /@ ran;
	rf = Sort[gOnMC - fOnMC];
	rg = Sort[fOnRan - gOnRan];
	lo = -rf[[-1]];
	hi =  rg[[-1]];
	{mlo, mhi} = MullerFunction[rf, rg] /@ {lo, hi};
	If[mlo <= 0 <= mhi,
		(* then: zero is in bounds *)
		Block[{x}, x /. FindRoot[
					MullerFunction[rf, rg][x],
					{x, .45*lo + .55*hi, .55*lo + .45*hi, lo, hi},
					FilterRules[{opts}, Options[FindRoot]] // Evaluate]],
		(* else: zero is out of bounds *)
		Message[MarginalLikelihoodMuller::badbounds, {mlo, mhi}];
		If[mlo > 0, lo, hi]]
	]

(* rf and rg are sorted logs of ratios *)
MullerFunction[rf_, rg_][x_?NumericQ] :=
	ComputeListSum[-x, rg] - ComputeListSum[x, rf]

(* the list is in logs and has been sorted *)
ComputeListSum =
	Compile[{
		{x, _Real, 0},
		{list, _Real, 1}},
	Module[{
		t = 0.,
		sum = 0.,
		len = Length[list]
		},
	Catch[
		Do[
		t = list[[i]] + x;
		If[t < 0,
			sum += 1 - Exp[t],
			Throw[sum/len]
			],
		{i, len}];
		sum/len]
	]];


(***** Chib-Jeliazkov method *****)

MarginalLikelihoodCJ[mc_, fun_, V_, xstar_, n_] :=
	Module[{ran, valstar, alphavals, qfun, qvals, num, den},
	ran = RandomReal[MultinormalDistribution[xstar, V], n];
	valstar = fun[xstar];
	alphavals = Min[0, valstar - #] & /@ mc[[All, 2]];
	qfun = With[{
			m = xstar,
			S = Inverse[V],
			const = -Log[(2Pi)^(Length[xstar]/2)Sqrt[Det[V]]]},
		Compile[{{z, _Real, 1}}, const - (z - m).S.(z - m)/2]
		];
	qvals = qfun /@ mc[[All, 1]];
	num = Mean[Exp[alphavals + qvals]];
	den = Mean[Exp[Min[0, fun[#] - valstar] & /@ ran]];
	valstar - Log[num/den]
	]


End[]
EndPackage[]

