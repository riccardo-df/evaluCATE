% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/generic-s3.R
\name{plot.evaluCATE}
\alias{plot.evaluCATE}
\title{Plot Method for evaluCATE Objects}
\usage{
\method{plot}{evaluCATE}(x, target = "GATES", ...)
}
\arguments{
\item{x}{An \code{evaluCATE} object.}

\item{target}{String controlling which plot to display. Must be either \code{"GATES"} or \code{"TOC"}.}

\item{...}{Further arguments passed to or from other methods.}
}
\value{
Plots an \code{evaluCATE} object.
}
\description{
Plots an \code{evaluCATE} object.
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

## CATEs estimation.
library(grf)

forest <- causal_forest(X_tr, Y_tr, D_tr) # We use only the training sample.
cates <- predict(forest, X)$predictions # We predict on the whole sample.

## CATEs evaluation. Estimate all nuisances internally. 
pscore <- rep(0.5, length(Y))
evaluation <- evaluCATE(Y, D, X, cates, train_idx, pscore = pscore)

## Plot.
plot(evaluation, target = "GATES")
plot(evaluation, target = "TOC")}

}
\author{
Riccardo Di Francesco
}
