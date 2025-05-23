# This code script is to update the ERS score calculation
# add an option for the include_int = T or F for more simple case of ERS scores

#######################################################3
#                                                      #
#             Citation for Original ERS Code           #
#                                                      #
#  Wang, Xin, Bhramar Mukherjee, and Sung Kyun Park.   #
#  “Associations of cumulative exposure to heavy metal #
#   mixtures with obesity and its comorbidities among  #
#   US adults in NHANES 2003–2014.”                    #
#   Environment international 121 (2018): 683-694.     #
#    doi:10.1016/j.envint.2018.09.035.                 #
#                                                      #
#    https://github.com/umich-biostatistics/ers        #
#                                                      #
#######################################################3


############## Function - ers.enet_adapt #####################

# A subfunction inside the wrapper function that
# performs the Elastic net algorithm on the exposure data

ers_enet_adapt = function(x,
                          y,
                          lambda2,
                          nfolds = 5,
                          foldid,
                          pf = rep(1, p),
                          pf2 = rep(1, p),
                          method = 'ls',
                          n_confound) {
  # a Function to format elapsed time
  format_elapsed_time <- function(elapsed_time) {
    if (elapsed_time < 60) {
      return(paste(elapsed_time, "seconds"))
    } else if (elapsed_time < 3600) {
      return(paste(round(elapsed_time / 60, 2), "minutes"))
    } else {
      return(paste(round(elapsed_time / 3600, 2), "hours"))
    }
  }
  
  # a function to count the number of selected variables
  count_selected_expos <- function(model, n_confound) {
    sum(gcdnet::coef(model) != 0)  - n_confound - 1 # for the intercept
  }
  
  # Start time
  start_time <- Sys.time()
  
  # 5 fold CV Elastic Net over the range of lambda2
  cv_lambda2 <- pbvapply(lambda2, function(lambda) {
    min(
      cv.gcdnet(
        x = x,
        y = y,
        lambda2 = lambda,
        nfolds = nfolds,
        foldid = foldid,
        pf = pf,
        pf2 = pf2,
        method = method
      )$cvm
    )
  }, FUN.VALUE = numeric(1))
  
  # Find the Optimal lambda2 and lambda1
  cv_lambda2_min <- lambda2[which.min(cv_lambda2)]
  cv_lambda1_min <- cv.gcdnet(
    x = x,
    y = y,
    lambda2 = cv_lambda2_min,
    nfolds = nfolds,
    foldid = foldid,
    method = method,
    pf = pf,
    pf2 = pf2
  )$lambda.min
  
  
  best_mod <- gcdnet(
    x = x,
    y = y,
    lambda = cv_lambda1_min,
    lambda2 = cv_lambda2_min,
    pf = pf,
    pf2 = pf2,
    method = method
  )
  
  
  if (count_selected_expos(best_mod, n_confound) < 3) {
    # Case when optimal lambda1 and lambda2 select less than 3 exposures
    
    print(
      paste(
        "The optimal Lambda 1 and Lambda 2 selects only",
        count_selected_expos(best_mod, n_confound),
        "exposures"
      )
    )
    print(paste("The cv.lambda1.min is", cv_lambda1_min))
    print(paste("The cv.lambda2.min is", cv_lambda2_min))
    print("Loop all possible lambda 1 values to select at least 3 exposures")
    
    # Find the Optimal lambda1 that selects at least 3 exposures
    cv_result <- cv.gcdnet(
      x = x,
      y = y,
      lambda2 = cv_lambda2_min,
      nfolds = nfolds,
      foldid = foldid,
      method = method,
      pf = pf,
      pf2 = pf2
    )
    
    lambda1_values <- cv_result$lambda
    optimal_lambda1 <- cv_result$lambda.min
    
    # Initialize progress bar
    pb <- progress_bar$new(
      format = "  Finding optimal lambda 1 values [:bar] :percent eta: :eta",
      total = length(lambda1_values),
      clear = FALSE,
      width = 60
    )
    
    for (lambda1 in lambda1_values) {
      model <- gcdnet(
        x = x,
        y = y,
        lambda = lambda1,
        lambda2 = cv_lambda2_min,
        pf = pf,
        pf2 = pf2,
        method = method
      )
      pb$tick()  # Update progress bar
      
      if (count_selected_expos(model, n_confound) >= 3) {
        optimal_lambda1 <- lambda1
        break
      }
    }
    
    if (is.null(optimal_lambda1)) {
      
      print(
        "No combination of lambda1 and lambda2 found that selects at least 3 exposures. Return the best model that minimizes least square error."
      )
      
      
      # End time
      end_time <- Sys.time()
      elapsed_seconds <- as.numeric(difftime(end_time, start_time, units = "secs"))
      print(paste("Elapsed time:", format_elapsed_time(elapsed_seconds)))
      
      # If no combination selects at least 3 exposures, use the minimum cross-validated lambda1
      
      return(best_mod)
    } else{
      print(paste("The optimal Lambda 1 value is now", optimal_lambda1))
      print(paste("The optimal Lambda 2 value is now", cv_lambda2_min))
      
      mod_atleast_3 <- gcdnet(
        x = x,
        y = y,
        lambda = optimal_lambda1,
        lambda2 = cv_lambda2_min,
        pf = pf,
        pf2 = pf2,
        method = method
      )
      
      print(
        paste(
          "The chosen Lambda 1 and Lambda 2 now selects",
          count_selected_expos(mod_atleast_3, n_confound),
          "exposures"
        )
      )
      
      # End time
      end_time <- Sys.time()
      elapsed_seconds <- as.numeric(difftime(end_time, start_time, units = "secs"))
      print(paste("Elapsed time:", format_elapsed_time(elapsed_seconds)))
      
      # return the best model with at least three variables chosen
      return(mod_atleast_3)
    }
    
  } else{
    # Case when optimal lambda1 and lambda2 select more than 3 exposures at first try
    print(
      paste(
        "The optimal Lambda 1 and Lambda 2 selects",
        count_selected_expos(best_mod, n_confound),
        "exposures"
      )
    )
    
    # End time
    end_time <- Sys.time()
    elapsed_seconds <- as.numeric(difftime(end_time, start_time, units = "secs"))
    print(paste("Elapsed time:", format_elapsed_time(elapsed_seconds)))
    
    # Return the Elastic Net results with optimal lambda settings
    return(best_mod)
  }
}


############## Function - ers.score_adapt #####################

ers_score_adapt = function(data, coef) {
  score <- data %*% coef
  colnames(score) = 'ERS'
  return(score)
}

############## Function - ers_Calc #######################

ers_Calc = function(data,
                    exposure,
                    outcome,
                    covar = NULL,
                    lambda2_start = NULL,
                    include_int = T,
                    method = 'ls',
                    scaled = FALSE,
                    nfolds = 5,
                    seed = NULL,
                    ...) {
  # require the needed pkgs
  pkgs <- c("dplyr", "gcdnet", "magrittr", "progress", "pbapply")
  suppressMessages(lapply(pkgs, require, character.only = T))
  
  if (!is.null(seed)) {
    set.seed(seed)
  }
  
  nobs <- dim(data)[1]
  n_train <- floor(nobs / 2)
  train_ids <- sort(sample(nobs, n_train))
  analysis_ids <- setdiff(1:nobs, train_ids)
  train_data <- data[train_ids, ]
  analysis_data <- data[analysis_ids, ]
  
  x_train <- train_data %>% dplyr::select(all_of(exposure)) %>% as.data.frame()
  y_train <- train_data[[outcome]] %>% as.matrix() %>% as.numeric()
  covar_train <- train_data %>% dplyr::select(all_of(covar)) %>% as.data.frame()
  x_analysis <- analysis_data %>% dplyr::select(all_of(exposure)) %>% as.data.frame()
  y_analysis <- analysis_data[[outcome]] %>% as.matrix() %>% as.numeric()
  covar_analysis <- analysis_data %>% dplyr::select(all_of(covar)) %>% as.data.frame()
  
  if (is.null(covar) == F) {
    if (any(!complete.cases(x_train)) |
        any(!complete.cases(y_train)) |
        any(!complete.cases(covar_train))) {
      stop('x, y, or covar contain missing values. This method requires complete data.')
    }
  } else{
    if (any(!complete.cases(x_train)) | any(!complete.cases(y_train))) {
      stop('x, y, or covar contain missing values. This method requires complete data.')
    }
  }
  
  if (is.null(lambda2_start)) {
    # auto-generate lambda2.start sequence.
  }
  
  foldid <- matrix(data = c(sample(n_train), rep(1:nfolds, length = n_train)),
                   nrow = n_train,
                   ncol = 2)
  foldid <- foldid[order(foldid[, 1]), ]
  foldid <- foldid[, 2]
  
  if (include_int == T) {
    # the complex case where the interactions, square terms are in the ENET var selection
    data_mod <- model.matrix( ~ -1 + .^2, data = x_train)
    x_sq <- x_train^2
    names(x_sq) <- paste0(names(x_train), '^2')
    
    if (is.null(covar) == F) {
      pf <- c(rep(1, ncol(data_mod) + ncol(x_sq)), rep(0, ncol(covar_train)))
      pf2 <- c(rep(1, ncol(data_mod) + ncol(x_sq)), rep(0, ncol(covar_train)))
      data_mod <- cbind(data_mod, x_sq, covar_train)
      
      tmp_data <- data_mod
      
      if (!isTRUE(scaled)) {
        data_mod <- as.matrix(apply(data_mod, 2, function(y) {
          scale(y, center = T, scale = T)
        }))
      }
      
    } else {
      pf <- c(rep(1, ncol(data_mod) + ncol(x_sq)))
      pf2 <- c(rep(1, ncol(data_mod) + ncol(x_sq)))
      data_mod <- cbind(data_mod, x_sq)
      
      tmp_data <- data_mod
      
      if (!isTRUE(scaled)) {
        data_mod <- as.matrix(apply(data_mod, 2, function(y) {
          scale(y, center = T, scale = T)
        }))
      }
      
    }
    
  } else {
    # the simple case with just the original exposures
    data_mod <- model.matrix( ~ -1 + ., data = x_train)
    
    if (is.null(covar) == F) {
      pf <- c(rep(1, ncol(data_mod)), rep(0, ncol(covar_train)))
      pf2 <- c(rep(1, ncol(data_mod)), rep(0, ncol(covar_train)))
      data_mod <- cbind(data_mod, covar_train)
      
      tmp_data <- data_mod
      
      if (!isTRUE(scaled)) {
        data_mod <- as.matrix(apply(data_mod, 2, function(y) {
          scale(y, center = T, scale = T)
        }))
      }
      
    } else {
      pf <- c(rep(1, ncol(data_mod)))
      pf2 <- c(rep(1, ncol(data_mod)))
      data_mod <- cbind(data_mod)
      
      tmp_data <- data_mod
      
      if (!isTRUE(scaled)) {
        data_mod <- as.matrix(apply(data_mod, 2, function(y) {
          scale(y, center = T, scale = T)
        }))
      }
      
    }
  }
  
  # ordinary Elastic net
  ers_fit <- ers_enet_adapt(data_mod,
                            y_train,
                            lambda2_start,
                            nfolds,
                            foldid,
                            pf,
                            pf2,
                            method,
                            ncol(covar_train))
  
  ers_beta <- as.matrix(coef(ers_fit))
  ers_beta_keep <- ers_beta != 0
  tab <- matrix(0, sum(ers_beta_keep), 1)
  rownames(tab) <- rownames(ers_beta)[ers_beta_keep]
  tab[, 1] <- ers_beta[ers_beta_keep, ]
  
  if (is.null(covar) == F) {
    tab_exposure <- subset(tab, !(row.names(tab) %in% c(
      '(Intercept)', colnames(covar_train)
    )))
  } else {
    tab_exposure <- subset(tab, !(row.names(tab) %in% c('(Intercept)')))
  }
  
  
  coef_enet <- as.numeric(tab_exposure)
  if (is.null(covar) == F) {
    if (any(!complete.cases(x_analysis)) |
        any(!complete.cases(y_analysis)) |
        any(!complete.cases(covar_analysis))) {
      stop('x, y, or covar contain missing values. This method requires complete data.')
    }
  } else{
    if (any(!complete.cases(x_analysis)) |
        any(!complete.cases(y_analysis))) {
      stop('x, y, or covar contain missing values. This method requires complete data.')
    }
  }
  
  if (is.null(lambda2_start)) {
    # auto-generate lambda2.start sequence.
  }
  
  if (include_int == T) {
    # the complex case where the interactions, square terms are in the ENET var selection
    data_mod <- model.matrix( ~ -1 + .^2, data = x_analysis)
    x_sq <- x_analysis^2
    names(x_sq) <- paste0(names(x_analysis), '^2')
    
    if (is.null(covar) == F) {
      data_mod <- cbind(data_mod, x_sq, covar_analysis)
      
      tmp_data <- rbind(tmp_data, data_mod)
      
      if (!isTRUE(scaled)) {
        data_mod <- as.matrix(apply(data_mod, 2, function(y) {
          scale(y, center = T, scale = T)
        }))
      }
      
    } else {
      data_mod <- cbind(data_mod, x_sq)
      
      tmp_data <- rbind(tmp_data, data_mod)
      
      if (!isTRUE(scaled)) {
        data_mod <- as.matrix(apply(data_mod, 2, function(y) {
          scale(y, center = T, scale = T)
        }))
      }
      
    }
    
  } else {
    # the simple case with just the original exposures
    data_mod <- model.matrix( ~ -1 + ., data = x_analysis)
    
    if (is.null(covar) == F) {
      data_mod <- cbind(data_mod, covar_analysis)
      
      tmp_data <- rbind(tmp_data, data_mod)
      
      if (!isTRUE(scaled)) {
        data_mod <- as.matrix(apply(data_mod, 2, function(y) {
          scale(y, center = T, scale = T)
        }))
      }
      
    } else {
      data_mod <- cbind(data_mod)
      
      tmp_data <- rbind(tmp_data, data_mod)
      
      if (!isTRUE(scaled)) {
        data_mod <- as.matrix(apply(data_mod, 2, function(y) {
          scale(y, center = T, scale = T)
        }))
      }
      
    }
  }
  dat_score <- as.matrix(data_mod[, rownames(tab_exposure)])
  
  # calculate the ERS score for each observation
  ers_scores <- ers_score_adapt(data = dat_score, coef = coef_enet)
  
  if (is.null(covar) == F) {
    tmp_data_noExpo <- data %>% dplyr::select(!all_of(exposure)) %>% dplyr::select(!all_of(covar))
  } else {
    tmp_data_noExpo <- data %>% dplyr::select(!all_of(exposure))
  }
  tmp_data <- tmp_data[order(c(train_ids, analysis_ids)), ]
  
  ERS <- rep(0, nobs)
  ERS[analysis_ids] <- ers_scores
  
  tmp_data <- cbind(tmp_data_noExpo, tmp_data, ERS)
  rownames(tmp_data) <- 1:nobs
  colnames(tmp_data) <- c(colnames(tmp_data)[1:(ncol(tmp_data) - 1)], "ERS")
  
  ers_obj <- list(
    post_ERS_data = tmp_data,
    ers_scores = ers_scores,
    # constructed ERS score
    ers_fit = ers_fit,
    # ENET result of Y ~ expanded X
    coef = coef_enet,
    # Coefficients of ENET
    dat_score = dat_score # exposures with non-zero effects after ENET
  )
  class(ers_obj) <- 'ers'
  
  return(ers_obj)
}
