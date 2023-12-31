% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/GATES.R
\name{test_parametric_gates}
\alias{test_parametric_gates}
\title{Testing for Effect Heterogeneity using the estimated GATES}
\usage{
test_parametric_gates(model)
}
\arguments{
\item{model}{Estimated parametric model, as one of those returned by \code{\link{gates_estimation}}.}
}
\value{
A list with the p-values for the three hypotheses tested.
}
\description{
Tests for effect heterogeneity using the estimated parametric model for the sorted group average treatment effects (GATES).
}
\details{
\code{model} must consist of a \code{lm_robust} object where the coefficients identifying the GATES must be called \code{"group1"}, \code{"group2"}, and so on.\cr

Three distinct hypotheses of effect heterogeneity are tested: whether all GATES are equal to each other, whether the largest and the smallest GATES are different from each other, 
and whether the differences in the GATES across all pairs of groups are zero. For the last test, we adjust p-values to account for multiple hypotheses testing using Holm's procedure 
and report the median of the adjusted p-values.
}
\examples{
\donttest{## Generate data.
set.seed(1986)

n <- 1000
k <- 2

X <- matrix(rnorm(n * k), ncol = k)
colnames(X) <- paste0("x", seq_len(k))
D <- rbinom(n, size = 1, prob = 0.5)
mu0 <- 0.5 * X[, 1]
mu1 <- 0.5 * X[, 1] + X[, 2]
Y <- mu0 + D * (mu1 - mu0) + rnorm(n)

## Sample split.
train_idx <- sample(c(TRUE, FALSE), length(Y), replace = TRUE)

X_tr <- X[train_idx, ]
X_val <- X[!train_idx, ]

D_tr <- D[train_idx]
D_val <- D[!train_idx]

Y_tr <- Y[train_idx]
Y_val <- Y[!train_idx]

## CATEs and nuisance functions estimation.
## We use only the training sample for estimation.
## We predict on the validation sample.
library(grf)

cates_forest <- causal_forest(X_tr, Y_tr, D_tr) 
mu_forest <- regression_forest(X_tr, Y_tr)
mu0_forest <- regression_forest(X_tr[D_tr == 0, ], Y_tr[D_tr == 0])
mu1_forest <- regression_forest(X_tr[D_tr == 1, ], Y_tr[D_tr == 1])

cates_val <- predict(cates_forest, X_val)$predictions 
mu_val <- predict(mu_forest, X_val)$predictions
mu0_val <- predict(mu0_forest, X_val)$predictions
mu1_val <- predict(mu1_forest, X_val)$predictions

## AIPW scores estimation.
## Cross-fitting on the validation sample.
library(aggTrees)
scores_val <- dr_scores(Y_val, D_val, X_val)

## GATEs estimation. Use default of five groups.
pscore_val <- rep(0.5, length(Y_val)) # We know true pscores.
gates_results <- gates_estimation(Y_val, D_val, cates_val, 
                                  pscore_val, mu_val, mu0_val, mu1_val, 
                                  scores_val)}

}
\seealso{
\code{\link{gates_estimation}}
}
\author{
Riccardo Di Francesco
}
