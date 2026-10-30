// Todos los importes son centavos. Solo se cuentan cobros aprobados.
export const categories={EGRESO:'Capital entregado / ajuste de egresos',INGRESO:'Capital recibido / ajuste de ingresos',INTERES:'Interés cobrado',ACTIVACION:'Activación cobrada',PUNTOS:'Compra de puntos cobrada',OTRA_GANANCIA:'Otra ganancia cobrada',GASTO:'Gasto del negocio',RETIRO:'Retiro personal'};
export function summarize(s){
 const approved=s.receipts.filter(r=>r.status==='APROBADO');
 const sum=(a,f)=>a.reduce((n,x)=>n+f(x),0);
 let interest=0;
 for(const l of s.loans){
  const receipts=approved.filter(r=>r.loan_id===l.id&&['CUOTA','LIQUIDACION'].includes(r.kind));
  if(l.status==='LIQUIDADO'){
   // La liquidación devuelve todo el capital; el excedente efectivamente cobrado es interés.
   interest+=Math.max(0,sum(receipts,r=>r.verified)-l.amount);
  }else{
   for(const q of s.installments.filter(q=>q.loan_id===l.id)){
    const paid=sum(receipts.filter(r=>r.kind==='CUOTA'&&r.installment_id===q.id),r=>r.verified);
    // Pagos parciales: distribución proporcional, redondeada una vez por cuota.
    interest+=Math.round(q.interest*Math.min(paid,q.amount)/q.amount);
   }
  }
 }
 const v={out:sum(s.loans,l=>l.amount),income:sum(approved,r=>r.verified),interest,activation:sum(approved.filter(r=>r.kind==='ACTIVACION'),r=>r.verified),points:sum(approved.filter(r=>r.kind==='PUNTOS'),r=>r.verified),other:0,expenses:0,withdrawals:0};
 for(const a of s.summary_adjustments||[]){
  const n=Number(a.amount);
  if(['EGRESO','GASTO','RETIRO'].includes(a.category))v.out+=n;else v.income+=n;
  const key={INTERES:'interest',ACTIVACION:'activation',PUNTOS:'points',OTRA_GANANCIA:'other',GASTO:'expenses',RETIRO:'withdrawals'}[a.category];if(key)v[key]+=n;
 }
 v.profit=v.interest+v.activation+v.points+v.other-v.expenses;
 return v;
}
