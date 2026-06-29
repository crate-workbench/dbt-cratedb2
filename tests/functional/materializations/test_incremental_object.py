from dbt.tests.util import run_dbt
import pytest


# Regression test for https://github.com/crate/dbt-cratedb2/issues/10
#
# CrateDB exposes OBJECT sub-fields (e.g. classification['type']) as separate
# columns in information_schema. On the second `dbt run`, the incremental
# delete+insert strategy used to list those bracketed sub-fields in its INSERT
# column list, which CrateDB rejects with `Column classification['type'] unknown`.
_MODEL = """
{{ config(materialized='incremental', incremental_strategy='delete+insert', unique_key='id') }}
select 1 as id, {type = 'a', labels = ['x', 'y']} as classification, 'bob' as username
"""


class TestIncrementalObjectColumns:
    @pytest.fixture(scope="class")
    def models(self):
        return {"obj_model.sql": _MODEL}

    def test_second_run_with_object_column(self, project):
        # First run takes the create branch and never lists columns.
        assert len(run_dbt(["run"])) == 1
        # Second run goes through delete+insert; this regressed before the fix.
        assert len(run_dbt(["run"])) == 1
