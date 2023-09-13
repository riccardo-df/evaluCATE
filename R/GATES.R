#' GATES Estimation
#'
#' Estimates the sorted group average treatment effects (GATES), with the groups formed by cutting the distribution of the estimated CATEs into K quantiles.
#'
#' @param Y Observed outcomes.
#' @param D Treatment indicator.
#' @param cates Estimated CATEs. CATEs must be estimated with different observations than those in \code{y} and \code{D}.
#' @param cates Estimated CATEs. Must be estimated with different observations than those in \code{Y} and \code{D}.
#' @param pscore Propensity scores. If unknown, must be estimated using different observations than those in \code{Y} and \code{D}. 
#' @param mu Estimated regression function. Must be estimated with different observations than those in \code{Y} and \code{D}. 
#' @param mu0 Estimated regression function for control units. Must be estimated with different observations than those in \code{Y} and \code{D}.
#' @param mu1 Estimated regression function for treated units. Must be estimated with different observations than those in \code{Y} and \code{D}. 
#' @param scores Estimated doubly-robust scores. Must be estimated via K-fold cross-fitting with the same observations as in \code{Y} and \code{D}.
#' @param n_groups Number of groups to be formed.
#'
#' @return
#' A list of fitted models as \code{\link[estimatr]{lm_robust}} objects and a data frame with point estimates and standard errors for the nonparametric estimator.
#'
#' @examples
#' ## Generate data.
#' set.seed(1986)
#' 
#' n <- 1000
#' k <- 2
#' 
#' X <- matrix(rnorm(n * k), ncol = k)
#' colnames(X) <- paste0("x", seq_len(k))
#' D <- rbinom(n, size = 1, prob = 0.5)
#' mu0 <- 0.5 * X[, 1]
#' mu1 <- 0.5 * X[, 1] + X[, 2]
#' Y <- mu0 + D * (mu1 - mu0) + rnorm(n)
#' 
#' ## Sample split.
#' train_idx <- sample(c(TRUE, FALSE), length(Y), replace = TRUE)
#' 
#' X_tr <- X[train_idx, ]
#' X_val <- X[!train_idx, ]
#' 
#' D_tr <- D[train_idx]
#' D_val <- D[!train_idx]
#' 
#' Y_tr <- Y[train_idx]
#' Y_val <- Y[!train_idx]
#' 
#' ## CATEs and nuisance functions estimation.
#' ## We use only the training sample for estimation.
#' ## We predict on the validation sample.
#' library(grf)
#' 
#' cates_forest <- causal_forest(X_tr, Y_tr, D_tr) 
#' mu_forest <- regression_forest(X_tr, Y_tr)
#' mu0_forest <- regression_forest(X_tr[D_tr == 0, ], Y_tr[D_tr == 0])
#' mu1_forest <- regression_forest(X_tr[D_tr == 1, ], Y_tr[D_tr == 1])
#' 
#' cates_val <- predict(cates_forest, X_val)$predictions 
#' mu_val <- predict(mu_forest, X_val)$predictions
#' mu0_val <- predict(mu0_forest, X_val)$predictions
#' mu1_val <- predict(mu1_forest, X_val)$predictions
#' 
#' ## AIPW scores estimation.
#' ## Cross-fitting on the validation sample.
#' library(aggTrees)
#' scores_val <- dr_scores(Y_val, D_val, X_val)
#' 
#' ## GATEs estimation. Use default of five groups.
#' pscore_val <- rep(0.5, length(Y_val)) # We know true pscores.
#' gates_results <- gates_estimation(Y_val, D_val, cates_val, 
#'                                   pscore_val, mu_val, mu0_val, mu1_val, 
#'                                   scores_val)
#'
#' @details
#' To estimate the GATES, the user must provide observations on the outcomes and the treatment status of units in 
#' the validation sample, as well as their estimated cates and nuisance functions. Be careful, as these estimates must be obtained using only observations from the training sample 
#' (see the example section below). Additionally, the user must provide doubly-robust scores estimated in the validation sample using K-fold cross fitting.\cr
#' 
#' The GATES are estimated using four different strategies: three involving fitting suitable linear models, and one nonparametric approach.  Check the online 
#' \href{https://riccardo-df.github.io/evaluCATE/articles/evalue-cates-short-tutorial.html}{short tutorial} for details.\cr
#' 
#' Each strategy based on linear models supports different model specifications 
#' that differ in additional and optional covariates that can be included in the regressions to reduce the estimation variance.
#' Check \href{https://riccardo-df.github.io/evaluCATE/articles/denoising.html}{denoising vignette} for details.\cr
#' 
#' For the linear models, standard errors are estimated using the Eicker-Huber-White estimator.\cr
#' 
#' Groups are constructed by cutting the distribution of \code{cates} into \code{n_groups} quantiles. If this leads to one or more groups composed of only treated or only control units, the function raises an error.\cr
#' 
#' The GATES estimated by the linear models are rearranged to obey the monotonicity property (i.e., we sort them in increasing order).\cr
#'
#' @import estimatr GenericML evalITR
#'
#' @author Riccardo Di Francesco
#'
#' @seealso \code{\link{blp_estimation}}, \code{\link{toc_estimation}}, \code{\link{rate_estimation}}
#'
#' @export
gates_estimation <- function(Y, D, cates, pscore, mu, mu0, mu1, scores, n_groups = 5) {
  ## 0.) Handling inputs and checks.
  if (n_groups <= 1 | n_groups %% 1 != 0) stop("Invalid 'n_groups'. This must be an integer greater than 1.", call. = FALSE)

  ## 1.) Generate groups by cutting the distribution of the CATEs. If we have homogeneous groups (i.e., only treated or only control units), raise an error.  
  cuts <- seq(0, 1, length = n_groups+1)[-c(1, n_groups+1)]
  group_indicators <- GenericML::quantile_group(cates, cutoffs = cuts)
  class(group_indicators) <- "numeric"
  colnames(group_indicators) <- paste0("gamma", 1:dim(group_indicators)[2])
  
  out_condition <- FALSE
  for (g in seq_len(dim(group_indicators)[2])) {
    if (sum(D[group_indicators[, g] == 0]) %in% c(0, dim(group_indicators)[1])) out_condition <- TRUE 
  }
  
  if (out_condition) stop("We have one or more homogeneous groups. Please try a different 'k' or a different sample split.", call. = FALSE)
  
  ## 2.) Construct covariates.
  wr_weights <- (pscore * (1 - pscore))^(-1) 
  D_residual <- D - pscore
  D_residual_interaction <- D_residual * group_indicators
  colnames(D_residual_interaction) <- paste0("gamma", 1:dim(D_residual_interaction)[2])
  pscore_interaction <- pscore * group_indicators
  colnames(pscore_interaction) <- paste0("pscore", 1:dim(D_residual_interaction)[2])
  H <- D_residual * wr_weights
  HY <- H * Y
  Hmu0 <- H * mu0
  Hpscore_interaction <- H * pscore_interaction
  colnames(Hpscore_interaction) <- paste0("H.pscore", 1:dim(group_indicators)[2])
  new_mck_covariate <- H * (1 - pscore) * cates
  Hpscore <- H * pscore
  Hmu0_pscore <- H * mu0 * pscore
  Hmu1_pscore <- H * mu1 * (1 - pscore)
  Hmu0_pscore_mu1_pscore <- Hmu0_pscore + Hmu1_pscore
  
  ## 3.) Define specifications.
  wr_none_dta <- data.frame("Y" = Y, D_residual_interaction)
  wr_cddf1_dta <- data.frame("Y" = Y, D_residual_interaction, mu0)
  wr_cddf2_dta <- data.frame("Y" = Y, D_residual_interaction, mu0, pscore_interaction)
  wr_mck1_dta <- data.frame("Y" = Y, D_residual_interaction, mu)
  
  ht_none_dta <- data.frame("HY" = HY, group_indicators)
  ht_cddf1_dta <- data.frame("HY" = HY, group_indicators, "H.mu0" = Hmu0)
  ht_cddf2_dta <- data.frame("HY" = HY, group_indicators, "H.mu0" = Hmu0, Hpscore_interaction)
  ht_mck1_dta <- data.frame("HY" = HY, group_indicators, "H.mu0" = Hmu0, "H.1-pscore.tauhat" = new_mck_covariate)
  ht_mck2_dta <- data.frame("HY" = HY, group_indicators, "H.pscore" = Hpscore, "H.mu0.pscore" = Hmu0_pscore, "h.mu1.1_pscore" = Hmu1_pscore)
  ht_mck3_dta <- data.frame("HY" = HY, group_indicators, "H.pscore" = Hpscore, "H.mu0.pscore+H.mu1.1_pscore" = Hmu0_pscore_mu1_pscore)
  
  aipw_dta <- data.frame("aipw" = scores, group_indicators)
  
  ## 4.) Fit linear models.
  wr_none_model <- estimatr::lm_robust(Y ~ 0 + ., wr_none_dta, weights = wr_weights, se_type = "HC1") 
  wr_cddf1_model <- estimatr::lm_robust(Y ~ 0 + ., wr_cddf1_dta, weights = wr_weights, se_type = "HC1") 
  wr_cddf2_model <- estimatr::lm_robust(Y ~ 0 + ., wr_cddf2_dta, weights = wr_weights, se_type = "HC1") 
  wr_mck1_model <- estimatr::lm_robust(Y ~ 0 + ., wr_mck1_dta, weights = wr_weights, se_type = "HC1") 
  
  ht_none_model <- estimatr::lm_robust(HY ~ 0 + ., ht_none_dta, se_type = "HC1") 
  ht_cddf1_model <- estimatr::lm_robust(HY ~ 0 + ., ht_cddf1_dta, se_type = "HC1") 
  ht_cddf2_model <- estimatr::lm_robust(HY ~ 0 + ., ht_cddf2_dta, se_type = "HC1") 
  ht_mck1_model <- estimatr::lm_robust(HY ~ 0 + ., ht_mck1_dta, se_type = "HC1") 
  ht_mck2_model <- estimatr::lm_robust(HY ~0 + ., ht_mck2_dta, se_type = "HC1") 
  ht_mck3_model <- estimatr::lm_robust(HY ~ 0 + ., ht_mck3_dta, se_type = "HC1") 
  
  aipw_model <- estimatr::lm_robust(aipw ~ 0 + ., aipw_dta, se_type = "HC1") 
  
  ## 5.) Enforce monotonicity and construct output.
  models <- list(wr_none_model, wr_cddf1_model, wr_cddf2_model, wr_mck1_model, 
                 ht_none_model, ht_cddf1_model, ht_cddf2_model, ht_mck1_model, ht_mck2_model, ht_mck3_model,
                 aipw_model)
  out <- list()
  counter <- 1
  
  for (model in models) {
    coef <- sort(model$coefficients[1:n_groups])
    names(coef) <- paste0("gamma", 1:n_groups)
    model$coefficients[1:n_groups] <- coef
    
    out[[counter]] <- model
    counter <- counter + 1
  }
  
  ## 6.) Nonparametric estimator.
  imai_li <- evalITR::GATE(D, cates, Y, n_groups)
  imai_li_results <- data.frame("group" = 1:n_groups, "GATE" = imai_li$gate, "SE" = imai_li$sd)
  
  ## 7.) Output.
  out[[counter]] <- imai_li_results
  names(out) <- c("wr_none", "wr_cddf1", "wr_cddf2", "wr_mck1",
                  "ht_none", "ht_cddf1", "ht_cddf2", "ht_mck1", "ht_mck2", "ht_mck3",
                  "aipw",
                  "imai_li")
  return(out)
}