import test from 'node:test';
import assert from 'node:assert/strict';
import {summarize} from '../summary.js';
const state=()=>({loans:[{id:'l',amount:10000,status:'ACTIVO'}],installments:[{id:'q1',loan_id:'l',amount:11200,interest:1200}],receipts:[],summary_adjustments:[]});
test('el capital desembolsado y los intereses pendientes no son ganancias',()=>{
 const v=summarize(state());assert.equal(v.out,10000);assert.equal(v.income,0);assert.equal(v.profit,0);
});
test('cobros parciales, activaciones y puntos; excluye pendientes y rechazados',()=>{
 const s=state();s.receipts=[{loan_id:'l',installment_id:'q1',kind:'CUOTA',status:'APROBADO',verified:2800},{loan_id:'l',installment_id:'q1',kind:'CUOTA',status:'APROBADO',verified:2800},{kind:'ACTIVACION',status:'APROBADO',verified:100},{kind:'PUNTOS',status:'APROBADO',verified:300},{kind:'PUNTOS',status:'PENDIENTE',verified:300},{kind:'ACTIVACION',status:'RECHAZADO',verified:100}];
 const v=summarize(s);assert.equal(v.income,6000);assert.equal(v.interest,600);assert.equal(v.profit,1000);
});
test('liquidación anticipada no cobra intereses futuros ni duplica pagos parciales',()=>{
 const s=state();s.loans[0].status='LIQUIDADO';s.receipts=[{loan_id:'l',installment_id:'q1',kind:'CUOTA',status:'APROBADO',verified:2800},{loan_id:'l',kind:'LIQUIDACION',status:'APROBADO',verified:7700}];
 const v=summarize(s);assert.equal(v.income,10500);assert.equal(v.interest,500);assert.equal(v.profit,500);
});
test('movimientos externos separan capital, retiros, gastos y ganancias',()=>{
 const s=state();s.summary_adjustments=[{category:'EGRESO',amount:20000},{category:'INGRESO',amount:20000},{category:'INTERES',amount:1000},{category:'ACTIVACION',amount:100},{category:'PUNTOS',amount:300},{category:'OTRA_GANANCIA',amount:200},{category:'GASTO',amount:250},{category:'RETIRO',amount:5000},{category:'INGRESO',amount:-100}];
 const v=summarize(s);assert.equal(v.out,35250);assert.equal(v.income,21500);assert.equal(v.profit,1350);assert.equal(v.withdrawals,5000);
 // Revertir conserva los originales y suma un registro contrario.
 s.summary_adjustments.push({category:'INTERES',amount:-1000});assert.equal(summarize(s).profit,350);assert.equal(s.loans[0].amount,10000);
});
test('las nuevas operaciones siguen sumando después de un ajuste exacto',()=>{
 const s=state();s.summary_adjustments.push({category:'INGRESO',amount:5000});
 s.receipts.push({kind:'ACTIVACION',status:'APROBADO',verified:100});
 assert.equal(summarize(s).income,5100);assert.equal(summarize(s).profit,100);
});
test('redondea al centavo sobre el total de una cuota, no por comprobante',()=>{
 const s=state();s.installments[0]={id:'q1',loan_id:'l',amount:3,interest:1};
 s.receipts=[1,1].map(verified=>({loan_id:'l',installment_id:'q1',kind:'CUOTA',status:'APROBADO',verified}));
 assert.equal(summarize(s).interest,1);
});
