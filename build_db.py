import sqlite3, random, datetime as dt
random.seed(7)
con = sqlite3.connect('/mnt/user-data/outputs/sql_lab_project/lab.db')
c = con.cursor()
c.executescript("""
DROP TABLE IF EXISTS orders; DROP TABLE IF EXISTS tests; DROP TABLE IF EXISTS analyzers; DROP TABLE IF EXISTS patients;
CREATE TABLE analyzers(analyzer_id INTEGER PRIMARY KEY, analyzer_name TEXT, section TEXT);
CREATE TABLE tests(test_id INTEGER PRIMARY KEY, test_name TEXT, section TEXT, target_tat_min INTEGER);
CREATE TABLE patients(patient_id INTEGER PRIMARY KEY, gender TEXT, age INTEGER, ward TEXT);
CREATE TABLE orders(order_id INTEGER PRIMARY KEY, patient_id INTEGER, test_id INTEGER, analyzer_id INTEGER,
  collected_at TEXT, received_at TEXT, resulted_at TEXT, shift TEXT, result_value REAL, is_critical INTEGER, is_repeated INTEGER,
  FOREIGN KEY(patient_id) REFERENCES patients(patient_id), FOREIGN KEY(test_id) REFERENCES tests(test_id), FOREIGN KEY(analyzer_id) REFERENCES analyzers(analyzer_id));
""")
analyzers=[(1,'Chem-A','Biochemistry'),(2,'Chem-B','Biochemistry'),(3,'Immuno-A','Immunology'),(4,'Immuno-B','Immunology'),(5,'Hema-A','Hematology'),(6,'Hema-B','Hematology'),(7,'Coag-A','Coagulation')]
c.executemany("INSERT INTO analyzers VALUES(?,?,?)",analyzers)
tests=[(1,'Glucose','Biochemistry',45),(2,'Creatinine','Biochemistry',45),(3,'Potassium','Biochemistry',30),(4,'Troponin I','Immunology',60),(5,'TSH','Immunology',120),
(6,'CBC','Hematology',45),(7,'HbA1c','Hematology',90),(8,'PT/INR','Coagulation',45),(9,'APTT','Coagulation',45),(10,'ALT','Biochemistry',60)]
c.executemany("INSERT INTO tests VALUES(?,?,?,?)",tests)
wards=['ICU','CCU','Operations','OPD','Ward']
wardw=[15,20,15,35,15]
pats=[(i,random.choice('MF'),random.randint(1,90),random.choices(wards,wardw)[0]) for i in range(1,2001)]
c.executemany("INSERT INTO patients VALUES(?,?,?,?)",pats)
pward={p[0]:p[3] for p in pats}
byA={}
for a in analyzers: byA.setdefault(a[2],[]).append(a[0])
rng={1:(70,180),2:(.5,2),3:(3.5,5.5),4:(0,.4),5:(.5,4.5),6:(10,15),7:(4.5,8),8:(1,1.6),9:(25,40),10:(10,60)}
rows=[];start=dt.datetime(2026,7,1)
for oid in range(1,20001):
    day=random.randint(0,89); hr=random.choices(range(24),[1,1,1,1,1,2,3,6,9,10,9,8,7,6,6,5,4,3,3,2,2,1,1,1])[0]
    col=start+dt.timedelta(days=day,hours=hr,minutes=random.randint(0,59))
    t=random.choice(tests); aid=random.choice(byA[t[2]]); p=random.choice(pats)
    ward=p[3]
    transit=random.randint(5,25)+(10 if ward=='OPD' else 0)
    proc=int(random.gauss(t[3]*0.55,t[3]*0.2)); proc=max(8,proc)
    if aid in(2,6) and random.random()<.25: proc+=random.randint(15,45)   # B analyzers slower
    if 14<=hr<=22: proc+=random.randint(0,12)
    rec=col+dt.timedelta(minutes=transit); res=rec+dt.timedelta(minutes=proc)
    shift='Morning' if 7<=hr<15 else 'Evening' if 15<=hr<23 else 'Night'
    lo,hi=rng[t[0]]; v=round(random.uniform(lo*.8,hi*1.4),2)
    crit=1 if (ward in('ICU','CCU') and random.random()<.06) or random.random()<.015 else 0
    rep=1 if random.random()<(.08 if aid in(2,6) else .04) else 0
    rows.append((oid,p[0],t[0],aid,col.isoformat(' '),rec.isoformat(' '),res.isoformat(' '),shift,v,crit,rep))
c.executemany("INSERT INTO orders VALUES(?,?,?,?,?,?,?,?,?,?,?)",rows)
c.execute("CREATE INDEX ix_o_test ON orders(test_id)"); c.execute("CREATE INDEX ix_o_an ON orders(analyzer_id)")
con.commit()
print(c.execute("select count(*) from orders").fetchone())
