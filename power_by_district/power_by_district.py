from airflow import DAG
from operators.common_pipeline import CommonDag


def _transfer(**kwargs):
    """
    Monthly power consumption (kWh sold) per district for Taipei + New Taipei.

    Source CSV columns (Chinese):
        年度, 月份, 郵遞區號, 行政區, 項目, 用戶數(戶), 契約容量(kW), 售電度數(度)

    Notes
    -----
    - 年度 is in ROC year (民國年). Convert with year + 1911.
    - Mask values '*' / '**' (個資保護) are coerced to NULL before numeric cast.
    - 「小計」/「合計」/「總計」rows are excluded to prevent double-counting.
    - 行政區 normalization:
        * Taipei rows already end with '區' (e.g. '中正區').
        * New Taipei rows do NOT end with '區' (e.g. '板橋'). We append '區'
          when the zipcode starts with '2' (新北市 220-253) AND the town
          name does not already end with '區'/'市'.
        * This is required so that town joins to taipei_town.geojson and
          new_taipei_town.geojson on the TNAME property.
    """
    import pandas as pd
    from sqlalchemy import create_engine
    from utils.load_stage import (
        save_dataframe_to_postgresql,
        update_lasttime_in_data_to_dataset_info,
    )
    from utils.get_time import get_tpe_now_time_str

    ready_data_db_uri = kwargs.get("ready_data_db_uri")
    dag_infos = kwargs.get("dag_infos")
    dag_id = dag_infos.get("dag_id")
    load_behavior = dag_infos.get("load_behavior")
    default_table = dag_infos.get("ready_data_default_table")
    history_table = dag_infos.get("ready_data_history_table")

    CSV_PATH = r"C:\Users\kk865\OneDrive\Desktop\taipei-dashboard\Taipei-City-Dashboard-box755\dist_kwh_114.csv"
    raw = pd.read_csv(CSV_PATH, encoding="utf-8-sig", dtype=str)

    df = raw.rename(
        columns={
            "年度": "roc_year",
            "月份": "month",
            "郵遞區號": "zipcode",
            "行政區": "town",
            "項目": "category",
            "用戶數(戶)": "users",
            "契約容量(kW)": "contract_kw",
            "售電度數(度)": "kwh_sold",
        }
    )

    for col in ["users", "contract_kw", "kwh_sold"]:
        df[col] = pd.to_numeric(
            df[col].replace(["*", "**", "***"], None), errors="coerce"
        )

    df["year"] = df["roc_year"].astype(int) + 1911
    df["month"] = df["month"].astype(int)
    df["zipcode"] = df["zipcode"].astype(str).str.strip().str.zfill(3)
    df["town"] = df["town"].astype(str).str.strip()
    df["category"] = df["category"].astype(str).str.strip()

    df = df[
        ~df["category"].str.contains("小計|合計|總計", na=False, regex=True)
    ].copy()

    # Restrict to Taipei (100-116) + New Taipei (200-253)
    df = df[df["zipcode"].str[0].isin(["1", "2"])].copy()
    # 雙北 zipcode:
    #   臺北市: 100-116
    #   新北市: 207(萬里), 208(金山), 220-253 (其他)
    #   排除  : 200-206 基隆市, 209-212 連江縣
    df = df[
        ((df["zipcode"].str[0] == "1") & (df["zipcode"].str[:3].between("100", "116")))
        | (
            (df["zipcode"].str[0] == "2")
            & (
                df["zipcode"].str[:3].isin(["207", "208"])
                | df["zipcode"].str[:3].between("220", "253")
            )
        )
    ].copy()

    # Normalize town names: append '區' for New Taipei rows that lack it.
    needs_suffix = (
        (df["zipcode"].str[0] == "2")
        & (~df["town"].str.endswith(("區", "市")))
    )
    df.loc[needs_suffix, "town"] = df.loc[needs_suffix, "town"] + "區"

    # Tag city for downstream filtering convenience
    df["city"] = df["zipcode"].str[0].map({"1": "臺北市", "2": "新北市"})

    df["data_time"] = get_tpe_now_time_str(is_with_tz=True)

    ready_data = df[
        [
            "data_time",
            "year",
            "month",
            "zipcode",
            "city",
            "town",
            "category",
            "users",
            "contract_kw",
            "kwh_sold",
        ]
    ]

    engine = create_engine(ready_data_db_uri)
    save_dataframe_to_postgresql(
        engine,
        data=ready_data,
        load_behavior=load_behavior,
        default_table=default_table,
        history_table=history_table,
    )

    lasttime_in_data = ready_data["data_time"].max()
    engine = create_engine(ready_data_db_uri)
    update_lasttime_in_data_to_dataset_info(
        engine, airflow_dag_id=dag_id, lasttime_in_data=lasttime_in_data
    )


dag = CommonDag(proj_folder="proj_city_dashboard", dag_folder="power_by_district")
dag.create_dag(etl_func=_transfer)
