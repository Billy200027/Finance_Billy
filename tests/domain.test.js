import test from 'node:test';import assert from 'node:assert/strict';import {simulate,firstSaturday,escape} from '../domain.js';
test('centavos exactos en todas las combinaciones válidas',()=>{for(let m=40;m<=1000;m+=5)for(let n=5;n<=20;n++){const s=simulate(m,n);assert.equal(Math.round((s.payment*(n-1)+s.last)*100),Math.round(s.total*100));assert.equal(s.total,Math.round((m+s.interest)*100)/100);}});
test('rechaza montos y plazos inválidos',()=>{for(const [m,n] of [[39,5],[41,5],[40,4],[40,21],[40,5.5],[NaN,5]])assert.throws(()=>simulate(m,n));});
test('ejemplo contractual de préstamo',()=>assert.deepEqual(simulate(100,5),{amount:100,weeks:5,interest:5.75,total:105.75,payment:21.15,last:21.15}));
test('domingo no usa el sábado inmediato',()=>assert.equal(firstSaturday('2027-05-02T15:00:00-05:00'),'2027-05-15'));
test('sábado usa el siguiente sábado',()=>assert.equal(firstSaturday('2027-05-01T23:59:59-05:00'),'2027-05-08'));
test('fechas alrededor de medianoche Ecuador',()=>assert.equal(firstSaturday('2027-05-02T04:30:00Z'),'2027-05-08'));
test('contenido de noticias se trata como texto',()=>assert.equal(escape('<script>alert("x")</script>'), '&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;'));
