# Indigo2-suite

The repo includes the codes, inputs, and scripts to run the experiments. There are 3 steyps to run the experiments and analyze the results.

## Step 1
Download the inputs and run all the codes through all the inputs
> sh run.sh

## Step 2
Read the throughputs and convert them to csv files
> sh generate_csv.sh

## Step 3
Update the csv file paths in the "analysis/analysis_*.ipynb"
Run the notebook to calculate metrics and generate figures for performance analysis
