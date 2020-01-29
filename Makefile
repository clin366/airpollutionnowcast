.PHONY: clean lint requirements train_model predict_model train_test_split

#################################################################################
# GLOBALS                                                                       #
#################################################################################

PROJECT_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
BUCKET = [OPTIONAL] your-bucket-for-syncing-data (do not include 's3://')
PROFILE = default
PROJECT_NAME = airpollutionnowcast
PYTHON_INTERPRETER = python3
ifeq (,$(shell which conda))
HAS_CONDA=False
else
HAS_CONDA=True
endif

#################################################################################
# VARIABLES                                                                       #
#################################################################################

CONFIG_PATH = config/parameters.ini
TRAIN_DATA_PATH = data/processed/common/train.csv
VALID_DATA_PATH = data/processed/common/valid.csv
TEST_DATA_PATH = data/processed/common/test.csv

#################################################################################
# PROJECT CONSTRUCT                                                                 #
#################################################################################
## Lint using flake8
lint:
	flake8 src

## Set up python interpreter environment
create_environment:
ifeq (True,$(HAS_CONDA))
	@echo ">>> Detected conda, creating conda environment."
	conda env create -f environment.yml --name $(PROJECT_NAME)
	conda activate $(PROJECT_NAME)
else
	@echo ">>> CONDA NEEDED TO CREATE ENVIRONMENT"
endif

## Test python environment is setup correctly
test_environment:
	conda activate $(PROJECT_NAME)
	$(PYTHON_INTERPRETER) test_environment.py

## Install Python Dependencies
requirements: test_environment
	$(PYTHON_INTERPRETER) -m pip install -U pip setuptools wheel
	$(PYTHON_INTERPRETER) -m pip install -r requirements.txt

#################################################################################
# COMMANDS                                                                      #
#################################################################################

## extract search trends
data/interim/search.csv:
	$(PYTHON_INTERPRETER) src/data/extract_search_trend.py $(CONFIG_PATH) $@

## extract pol labels
data/interim/pol.csv:
	$(PYTHON_INTERPRETER) src/data/extract_pol_label.py $(CONFIG_PATH) $@

## extract physical measurements data
data/interim/phys.csv:
	$(PYTHON_INTERPRETER) src/data/extract_phys_meas.py $(CONFIG_PATH) $@

## process physical measurements features
data/interim/process_phys.csv: data/interim/phys.csv
	$(PYTHON_INTERPRETER) src/data/process_phys_feature.py $(CONFIG_PATH) $< $@

## merge all data
data/interim/merged.csv: data/interim/pol.csv data/interim/search.csv data/interim/process_phys.csv
	$(PYTHON_INTERPRETER) src/data/merge_data_files.py $(CONFIG_PATH) $^ $@

## train test split into files
train_test_split: data/interim/merged.csv
	$(PYTHON_INTERPRETER) src/data/train_test_split.py $(CONFIG_PATH) $< $(TRAIN_DATA_PATH) $(VALID_DATA_PATH) $(TEST_DATA_PATH)

## train model
train_model:
	$(PYTHON_INTERPRETER) src/evaluation/train_model.py $(CONFIG_PATH) $(TRAIN_DATA_PATH) $(VALID_DATA_PATH)

## predict and get report
predict_model: 
	$(PYTHON_INTERPRETER) src/evaluation/predict_model.py $(CONFIG_PATH) $(TEST_DATA_PATH)

## Delete all compiled Python files
clean:
	find . -type f -name "*.py[co]" -delete
	find . -type d -name "__pycache__" -delete
	rm -f data/raw/*.csv
	rm -f data/interim/*.csv
	rm -f data/processed/*.csv
	rm -f models/*.h5
	rm -f models/*.pkl
	rm -f models/interim/*.h5
	rm -f reports/*.csv
	rm -f reports/*.ini



#################################################################################
# Self Documenting Commands                                                     #
#################################################################################

.DEFAULT_GOAL := help

# Inspired by <http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html>
# sed script explained:
# /^##/:
# 	* save line in hold space
# 	* purge line
# 	* Loop:
# 		* append newline + line to hold space
# 		* go to next line
# 		* if line starts with doc comment, strip comment character off and loop
# 	* remove target prerequisites
# 	* append hold space (+ newline) to line
# 	* replace newline plus comments by `---`
# 	* print line
# Separate expressions are necessary because labels cannot be delimited by
# semicolon; see <http://stackoverflow.com/a/11799865/1968>
.PHONY: help
help:
	@echo "$$(tput bold)Available rules:$$(tput sgr0)"
	@echo
	@sed -n -e "/^## / { \
		h; \
		s/.*//; \
		:doc" \
		-e "H; \
		n; \
		s/^## //; \
		t doc" \
		-e "s/:.*//; \
		G; \
		s/\\n## /---/; \
		s/\\n/ /g; \
		p; \
	}" ${MAKEFILE_LIST} \
	| LC_ALL='C' sort --ignore-case \
	| awk -F '---' \
		-v ncol=$$(tput cols) \
		-v indent=19 \
		-v col_on="$$(tput setaf 6)" \
		-v col_off="$$(tput sgr0)" \
	'{ \
		printf "%s%*s%s ", col_on, -indent, $$1, col_off; \
		n = split($$2, words, " "); \
		line_length = ncol - indent; \
		for (i = 1; i <= n; i++) { \
			line_length -= length(words[i]) + 1; \
			if (line_length <= 0) { \
				line_length = ncol - indent - length(words[i]) - 1; \
				printf "\n%*s ", -indent, " "; \
			} \
			printf "%s ", words[i]; \
		} \
		printf "\n"; \
	}' \
	| more $(shell test $(shell uname) = Darwin && echo '--no-init --raw-control-chars')
