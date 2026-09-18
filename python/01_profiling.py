import pandas as pd
import glob, os

files = sorted(glob.glob("raw_data/*.csv"))

for f in files:
    df = pd.read_csv(f)
    print("=" * 70)
    print(os.path.basename(f))
    print("Rows:", len(df), "| Columns:", len(df.columns))
    print("-" * 70)
    print(df.dtypes)
    print("-" * 70)
    print("Nulls per column:")
    print(df.isnull().sum())
    print("Exact duplicate rows:", df.duplicated().sum())
    print()
