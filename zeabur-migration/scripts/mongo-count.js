// 列出所有非系統資料庫的集合：「db.集合 筆數 idx=索引數 ttl=yes|no」，已排序。只讀，不印連線字串。
// 用法：在檔頭加一行 db = connect("<uri>"); 存成權限 600 的暫存檔，再 mongosh --nodb --quiet --file <暫存檔>。
// 不要把 uri 放在指令列（會出現在 ps 和 shell 歷史）。mongo-move.sh 已經這樣做。
const lines = [];
db.getMongo().getDBNames().filter(n => !['admin', 'local', 'config'].includes(n)).forEach(n => {
  const d = db.getSiblingDB(n);
  d.getCollectionInfos({ type: 'collection' }).forEach(ci => {
    const c = d.getCollection(ci.name);
    const idx = c.getIndexes();
    const ttl = idx.some(i => i.expireAfterSeconds !== undefined) ? 'yes' : 'no';
    lines.push(`${n}.${ci.name} ${c.countDocuments({})} idx=${idx.length} ttl=${ttl}`);
  });
});
lines.sort().forEach(l => print(l));
