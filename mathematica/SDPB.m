(* ::Package:: *)

(*Setup*)
prec = 200;

(* A matrix with constant anti-diagonals given by the list bs *)
antiBandMatrix[bs_] := Module[
    {n = Ceiling[Length[bs]/2]},
    Reverse[Normal[
        SparseArray[
            Join[
                Table[Band[{i, 1}] -> bs[[n - i + 1]], {i, n}],
                Table[Band[{1, i}] -> bs[[n + i - 1]], {i, 2, n}]],
            {n, n}]]]];

(* DampedRational[c, {p1, p2, ...}, b, x] stands for c b^x / ((x-p1)(x-p2)...) *)
(* It satisfies the following identities *)

DampedRational[const_, poles_, base_, x + a_] := 
    DampedRational[base^a const, # - a & /@ poles, base, x];

DampedRational[const_, poles_, base_, a_ /; FreeQ[a, x]] := 
    const base^a/Product[a - p, {p, poles}];

DampedRational/:x DampedRational[const_, poles_ /; MemberQ[poles, 0], base_, x] :=
    DampedRational[const, DeleteCases[poles, 0], base, x];


(* bilinearForm[f, m] = Integral[x^m f[x], {x, 0, Infinity}] *)
(* The special case when f[x] has no poles *)
bilinearForm[DampedRational[const_, {}, base_, x], m_] :=
    const Gamma[1+m] (-Log[base])^(-1-m);

memoizeGamma[a_,b_]:=memoizeGamma[a,b]=Gamma[a,b];

(* The general DampedRational case *)
bilinearForm[DampedRational[const_, poles_, base_, x], m_] := 
    const Sum[
        ((-poles[[i]])^m) ( base^poles[[i]]) Gamma[1 + m] memoizeGamma[-m, poles[[i]] Log[base]]/
        Product[poles[[i]] - p, {p, Delete[poles, i]}],
        {i, Length[poles]}];

(* orthogonalPolynomials[f, n] is a set of polynomials with degree 0
through n which are orthogonal with respect to the measure f[x] dx *)
orthogonalPolynomials[const_ /; FreeQ[const, x], 0] := {1/Sqrt[const]};

orthogonalPolynomials[const_ /; FreeQ[const, x], degree_] := 
    error["can't get orthogonal polynomials of nonzero degree for constant measure"];

orthogonalPolynomials[DampedRational[const_, poles_, base_, x], degree_] := 
    Table[x^m, {m, 0, degree}] . Inverse[
        CholeskyDecomposition[
            antiBandMatrix[
                Table[bilinearForm[DampedRational[const, Select[poles, # < 0&], base, x], m],
                      {m, 0, 2 degree}]]]];

(* Preparing SDP for Export *)
rho = SetPrecision[3-2 Sqrt[2], prec];

rescaledLaguerreSamplePoints[n_] := Table[
    SetPrecision[\[Pi]^2 (-1+4k)^2/(-64n Log[rho]), prec],
    {k,0,n-1}];

maxIndexBy[l_,f_] := SortBy[
    Transpose[{l,Range[Length[l]]}],
    -f[First[#]]&][[1,2]];

(* finds v' such that a . v = First[v'] + a' . Rest[v'] when normalization . a == 1, where a' is a vector of length one less than a *)
reshuffleWithNormalization[normalization_, v_] := Module[
    {j = maxIndexBy[normalization, Abs], const},
    const = v[[j]]/normalization[[j]];
    Prepend[Delete[v - normalization*const, j], const]];

(* XML Exporting *)
nf[x_Integer] := x;
nf[x_] := NumberForm[SetPrecision[x,prec],prec,ExponentFunction->(Null&)];

safeCoefficientList[p_, x_] := Module[
    {coeffs = CoefficientList[p, x]},
    If[Length[coeffs] > 0, coeffs, {0}]];

WriteBootstrapSDP[file_, SDP[objective_, normalization_, positiveMatricesWithPrefactors_]] := Module[
    {
        stream = OpenWrite[file],
        node, real, int, vector, polynomial,
        polynomialVector, polynomialVectorMatrix,
        affineObjective, polynomialVectorMatrices
    },

    (* write a single XML node to file.  children is a routine that writes child nodes when run. *)
    node[name_, children_] := (
        WriteString[stream, "<", name, ">"];
        children[];
        WriteString[stream, "</", name, ">\n"];
    );

    real[r_][] := WriteString[stream, nf[r]];
    int[i_][] := WriteString[stream, i];
    vector[v_][] := Do[node["elt", real[c]], {c, v}];
    polynomial[p_][] := Do[node["coeff", real[c]], {c, safeCoefficientList[p,x]}];
    polynomialVector[v_][] := Do[node["polynomial", polynomial[p]], {p, v}];

    polynomialVectorMatrix[PositiveMatrixWithPrefactor[prefactor_, m_]][] := Module[
        {degree = Max[Exponent[m, x]], samplePoints, sampleScalings, bilinearBasis},

        samplePoints   = rescaledLaguerreSamplePoints[degree + 1];
        sampleScalings = Table[prefactor /. x -> a, {a, samplePoints}];
        bilinearBasis  = orthogonalPolynomials[prefactor, Floor[degree/2]];

        node["rows", int[Length[m]]];
        node["cols", int[Length[First[m]]]];
        node["elements", Function[
            {},
            Do[node[
                "polynomialVector",
                polynomialVector[reshuffleWithNormalization[normalization,pv]]],
               {row, m}, {pv, row}]]];
        node["samplePoints", vector[samplePoints]];
        node["sampleScalings", vector[sampleScalings]];
        node["bilinearBasis", polynomialVector[bilinearBasis]];
    ];

    node["sdp", Function[
        {},
        node["objective", vector[reshuffleWithNormalization[normalization, objective]]];
        node["polynomialVectorMatrices", Function[
            {},
            Do[node["polynomialVectorMatrix", polynomialVectorMatrix[pvm]], {pvm, positiveMatricesWithPrefactors}];
        ]];
    ]];                                          

    Close[stream];
];