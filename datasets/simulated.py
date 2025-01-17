from benchopt import BaseDataset, safe_import_context
from benchopt.datasets.simulated import make_correlated_data

with safe_import_context() as import_ctx:
    from benchmark_utils.datasets import compute_w_l0pb


class Dataset(BaseDataset):
    name = "simulated"
    parameters = {
        "n_samples, n_features, density, rho, snr, random_state": [
            (30, 50, 0.1, 0.9, 10.0, None),
        ],
    }

    def __init__(self, **params):
        self.params = params

    def get_data(self):
        X, y, w_true = make_correlated_data(**self.params)
        w_l0pb = compute_w_l0pb(y, X, w_true)
        return dict(X=X, y=y, w_true=w_true, w_l0pb=w_l0pb)
