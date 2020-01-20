import ast
import configparser
import logging
import os
import pickle
import sys
from configparser import ExtendedInterpolation

import click
import pandas as pd

sys.path.append('.')
from src.evaluation.utils import process_features, result_stat, write_report, get_feature_from_config, \
    get_model_from_config, get_feature_pars, RECORD_COLUMNS
from src.data.utils import get_city_output_path


@click.command()
@click.argument('config_path', type=click.Path(exists=True))
@click.argument('test_data_path', type=click.Path(exists=True))
def extract_file(config_path, test_data_path):
    logger = logging.getLogger(__name__)
    logger.info('predict the testing data')

    pars = configparser.ConfigParser(interpolation=ExtendedInterpolation())
    pars.read(config_path)
    # automatically get commit id from environment
    commit_id = os.popen('git rev-parse HEAD').read().replace('\n', '')
    pars['DEFAULT']['commit_id'] = commit_id


    # global parameters
    seq_length = int(pars['train_model']['seq_length'])
    search_lag = int(pars['train_model']['search_lag'])
    # features_array = ast.literal_eval(pars['train_model']['FEATURE'])
    use_feature = ast.literal_eval(pars['train_model']['use_feature'])
    # report path
    report_path = pars['predict_model']['report_path']

    # if appending results
    append_mode = pars['predict_model'].getboolean('append_mode')
    # if city_mode; predict per city
    city_mode = pars['predict_model'].getboolean('city_mode')
    city = pars['predict_model']['city']

    if city_mode:
        test_data_path = get_city_output_path(test_data_path, city)

    if os.path.exists(report_path):
        print("Report File Exist! Change Report Path\n")
        if append_mode:
            record_pd = pd.read_csv(report_path, header=0, index_col=False)
            row_count = record_pd.shape[0] + 1
        else:
            exit(1)
    else:
        record_pd = pd.DataFrame(columns=RECORD_COLUMNS)
        row_count = 0

    # get feature_pars dict
    for index in use_feature:
        feature_pars = get_feature_pars(pars, index)
        # get model_type
        model_type = feature_pars['model_type']
        # save input_data_path for dllstm model
        feature_pars['input_data_path'] = test_data_path
        y_test, test_pol, test_phys, test_trend = process_features(test_data_path, seq_length, search_lag)

        # design for dllstm model
        if model_type == 'dllstm':
            # get common terms
            current_word_path = feature_pars['current_word_path']
            with open(current_word_path, 'rb') as f:
                common_terms = pickle.load(f)
            test_trend = test_trend[common_terms]

        x_test, embedding_dim = get_feature_from_config(feature_pars, test_pol, test_phys, test_trend)

        model = get_model_from_config(feature_pars, model_type, embedding_dim)
        # build model
        model.build_model()
        model.load(feature_pars['save_model_path'])

        pred_class, pred_score = model.predict(x_test)
        result_scores = result_stat(y_test, pred_class, pred_score)
        print(result_scores)
        result_scores = [city, model_type, feature_pars['feature'], feature_pars['is_two_branch'],
                         search_lag] + result_scores
        record_pd = write_report(result_scores, record_pd, row_count)
        row_count += 1

    # write results
    report_pardir = os.path.dirname(report_path)
    if not os.path.exists(report_pardir):
        os.makedirs(report_pardir)
    record_pd.to_csv(report_path, index=False, header=True)
    # save config file
    save_config_path = os.path.join(report_pardir, 'config.ini')
    with open(save_config_path, 'w') as configfile:
        pars.write(configfile)


if __name__ == '__main__':
    log_fmt = '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    logging.basicConfig(level=logging.INFO, format=log_fmt)

    extract_file()
