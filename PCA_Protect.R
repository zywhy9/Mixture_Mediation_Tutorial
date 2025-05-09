# This is the script to test out the PCA method for the PROTECT data example

# There are 175 samples

################################ Set up ############################

pkgs <- c(
  "tidyverse",
  "MASS",
  "CMAverse",
  "corrplot",
  "cluster",
  "factoextra",
  "ggbiplot",
  "ggfortify"
)

invisible(lapply(pkgs, library, character.only = T))

# Read in the data
list_headZscore <- read_rds("RDS/list_headZscore.rds")

set.seed(1211)

source("Functions/Functions_PCA.R")

################################# LTE4-headZscore (Phth only) - PCA MedTest #############################

## PCA generation
PCA_res_headZscore <- prcomp(list_headZscore[["Exposures"]] %>% as.data.frame(), scale. = TRUE)

# Check the cumulative explained variance of each PC
explained_variance <- summary(PCA_res_headZscore)$importance[3, ]
print(explained_variance)

(id_80var <- which.max(explained_variance >= 0.8))

# combine with the PCs that cumulatively explain 80% of the variance
list_headZscore[["PCA_Data"]] <- cbind(list_headZscore[["Data"]], PCA_res_headZscore$x[, 1:id_80var])

######################## Scree Plots Loadings Plots, Loading Heatmaps ########################3

## Scree plots
fviz_eig(
  PCA_res_headZscore,
  addlabels = T,
  choice = "variance",
  ncp = id_80var + 1
) +
  theme(text = element_text(size = 15)) +
  labs(x = "Principal Components", title = "")

# pdf("../pic/pca_data_scree.pdf", width = 8, height = 5)
# fviz_eig(PCA_res_headZscore, addlabels = T, choice = "variance", ncp = id_80var+1) +
#   theme(text = element_text(size = 15)) +
#   labs(x = "Principal Components", title = "")
# dev.off()
# tiff("../pic/pca_data_scree.tiff", width = 8, height = 5, units = "in", res = 800, compression = "lzw")
# fviz_eig(PCA_res_headZscore, addlabels = T, choice = "variance", ncp = id_80var+1) +
#   theme(text = element_text(size = 15)) +
#   labs(x = "Principal Components", title = "")
# dev.off()


## Create a heatmap of the loadings
# Convert loadings matrix to data frame
loadings_PCA_headZscore <- as.data.frame(PCA_res_headZscore$rotation[, 1:id_80var]) %>%
  rownames_to_column(var = "Exposures") %>%
  gather(Principal_Component, Loading, -Exposures)
loadings_PCA_headZscore$Exposures <- loadings_PCA_headZscore$Exposures %>% factor(levels = unique(loadings_PCA_headZscore$Exposures))


# Draw heat map
plot <- ggplot(loadings_PCA_headZscore,
               aes(y = Exposures, x = Principal_Component, fill = Loading)) +
  geom_tile(color = "grey") +
  scale_fill_gradient2(
    low = "blue",
    mid = "white",
    high = "red",
    midpoint = 0
  ) +
  scale_y_discrete(
    breaks = unique(loadings_PCA_headZscore$Exposures),
    labels = unique(loadings_PCA_headZscore$Exposures),
    expand = c(0, 0)
  ) +
  scale_x_discrete(expand = c(0, 0), limits = paste0("PC", 1:id_80var)) +
  labs(y = "Exposures", x = "Principal Component", title = "") +
  theme_bw() +
  theme(
    axis.text.y = element_text(size = 10, hjust = 1),
    text = element_text(size = 13),
    plot.background = element_blank(),
    panel.border = element_blank(),
    axis.ticks = element_blank()
  )
plot

# ggsave(
#   "pca_data_heat.pdf",
#   path = "../pic/",
#   plot = plot,
#   device = "pdf",
#   width = 8,
#   height = 5,
#   units = "in",
#   dpi = 800
# )
# tiff("../pic/pca_data_heat.tiff", width = 8, height = 5, units = "in", res = 800, compression = "lzw")
# print(plot)
# dev.off()


################################ PCA Mediation Effect Testing and estimation (expo as confounder) ###############3

# In this case, since there are 17 PC components to test
# we will use a single PC component as the exposures and test for mediation effect one at a time

confounders_nm <- colnames(list_headZscore[["Confounders"]])[!grepl("Intercept", colnames(list_headZscore[["Confounders"]]))]

mediator_nm <- "LTE4"
outcome_nm <- colnames(list_headZscore[["Data"]])[1]

## Mediation Test
set.seed(1211)
tictoc::tic()
list_headZscore[["medTest"]][["PCA"]] <- PCA_medTest(
  data = list_headZscore[["PCA_Data"]],
  nboot = 1000,
  outcome_nm = outcome_nm,
  mediator_nm = mediator_nm,
  confounders_nm = confounders_nm
)
tictoc::toc() # 43 secs

# extract the DE IE and TE of each PC component
tmp <- paste(c("CDE", "PNDE", "TNDE", "PNIE", "TNIE", "TE", "PM"), "Table")
tidy_res <- list()

for (new_df in tmp) {
  trgt <- str_to_lower(str_replace_all(new_df, " Table", ""))
  
  tidy_res[[new_df]] <- purrr::map_df(names(list_headZscore[["medTest"]][["PCA"]]), function(pc) {
    df <- list_headZscore[["medTest"]][["PCA"]][[pc]][["CMA Summary Table"]] %>% as.data.frame()
    trgt_row <- df[trgt, , drop = FALSE]  # Extract the target effect row
    trgt_row <- cbind(PC = pc, trgt_row)  # Add a column with the PC name
    trgt_row
  }, .id = NULL)
  # rename each row
  rownames(tidy_res[[new_df]]) <- tidy_res[[new_df]]$PC
  tidy_res[[new_df]] <- tidy_res[[new_df]] %>% dplyr::select(-PC)
}

list_headZscore[["medTest"]][["PCA"]][["Tidy Results"]] <- tidy_res

## BH correction for all the effects p-value
correct_trgt <- list_headZscore[["medTest"]][["PCA"]][["Tidy Results"]] %>% names

for (correct_id in correct_trgt) {
  list_headZscore[["medTest"]][["PCA"]][["Tidy Results"]][[correct_id]][["BH.Adj.Pval"]] <- list_headZscore[["medTest"]][["PCA"]][["Tidy Results"]][[correct_id]][["Pval"]] %>%
    p.adjust(method = "BH")
}

list_headZscore[["medTest"]][["PCA"]][["Tidy Results"]][["TNDE Table"]] %>% round(2)
list_headZscore[["medTest"]][["PCA"]][["Tidy Results"]][["PNIE Table"]] %>% round(2)
list_headZscore[["medTest"]][["PCA"]][["Tidy Results"]][["TE Table"]] %>% round(2)

write_rds(list_headZscore, "RDS/list_headZscore.rds")
