USE [INFORMESPOS]
GO
/**
   PROGRAMA: PRC_FE_OBTIENE_STRING_BASIC
   AUTOR: HUGO CASTAÑEDA
   FECHA: 2023-01-16
   PROPOSITO: RECIBE COMO PARAMETRO FECHA, TIENDA, CAJA Y TRANSACCIÓN. 
              DEVUELVE LLAMADO AL SERVICIO DE FACTURA ELECTRÓNICA PARA LA GENERACIÓN DE LA FACTURA POR CONTINGENCIA
   MODIFICACIONES:
   PROBAR ASÍ:
   EXEC PRC_FE_OBTIENE_STRING_BASIC '20221203', '17', '11', '37'
   EXEC PRC_FE_OBTIENE_STRING_BASIC '20221222', '922', '5', '2'
**/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[PRC_FE_OBTIENE_STRING_BASIC]
@FECHA VARCHAR(8),
@ALMACEN VARCHAR(8),
@TRM VARCHAR(8),
@TRAN VARCHAR(8)
AS
DECLARE @IMPT_BOLSA VARCHAR(12)='108046853797';
-- Borra tablas temporales:
IF OBJECT_ID('tempdb..#TMP_VTADPT_DET') IS NOT NULL DROP TABLE #TMP_VTADPT_DET -- Depto detalles por articulos
IF OBJECT_ID('tempdb..#TMP_VTADPT_DET_PRO') IS NOT NULL DROP TABLE #TMP_VTADPT_DET_PRO -- Detalles para productos propios
IF OBJECT_ID('tempdb..#TMP_VTADPT_PRO') IS NOT NULL DROP TABLE #TMP_VTADPT_PRO -- Depto para productos propios
IF OBJECT_ID('tempdb..#TMP_VTADPT_MND') IS NOT NULL DROP TABLE #TMP_VTADPT_MND -- Depto para productos de terceros
IF OBJECT_ID('tempdb..#TMP_VTAMP') IS NOT NULL DROP TABLE #TMP_VTAMP -- Encabezado de VTAXMP
IF OBJECT_ID('tempdb..#TMP_VTAMP_DET') IS NOT NULL DROP TABLE #TMP_VTAMP_DET -- Detalle de VTAXMP
IF OBJECT_ID('tempdb..#TMP_VTAMP_DET_MP') IS NOT NULL DROP TABLE #TMP_VTAMP_DET_MP -- Lineal de VTAXMP
IF OBJECT_ID('tempdb..#TMP_BONO_CAMBIO') IS NOT NULL DROP TABLE #TMP_BONO_CAMBIO -- Ajuste al cambio
IF OBJECT_ID('tempdb..#TMP_DCTO_GASTO') IS NOT NULL DROP TABLE #TMP_DCTO_GASTO -- Ajuste al cambio
IF OBJECT_ID('tempdb..#TMP_FISCAL') IS NOT NULL DROP TABLE #TMP_FISCAL -- Consecutivo fiscal
IF OBJECT_ID('tempdb..#TMP_ALMACEN') IS NOT NULL DROP TABLE #TMP_ALMACEN -- Datos del almacen
IF OBJECT_ID('tempdb..#TMP_VTAIVA_LINEAL') IS NOT NULL DROP TABLE #TMP_VTAIVA_LINEAL -- Detalle de impuestos
IF OBJECT_ID('tempdb..#TMP_VTAIVA_DET') IS NOT NULL DROP TABLE #TMP_VTAIVA_DET -- Lineal de impuestos
-- Crea tablas temporales:
--
-- Tabla con todos los detalles:
-- Comento las siguientes lineas para evitar JOIN con DB_SICAF, se cambia descripcion por el mismo EAN
--SELECT ROW_NUMBER() OVER(ORDER BY CANTIDAD) AS 'RowNumber', VST_DEPTO_HISTORICO.*, A.DESCRIPCION
SELECT ROW_NUMBER() OVER(ORDER BY CANTIDAD) AS 'RowNumber'
      , VST_DEPTO_HISTORICO.*
      , PRECIO / (1 + PORCENTAJE / 100.0) AS TOTAL_BRUTO
      , DESCUENTO / (1 + PORCENTAJE / 100.0) AS TOTAL_DESCUENTO
      , ' ITEM ' + CODIGO DESCRIPCION
INTO #TMP_VTADPT_DET
FROM VST_DEPTO_HISTORICO
WHERE FECHA_POS = @FECHA
          AND ALMACEN_POS = @ALMACEN
          AND TERM = RIGHT('0000'+@TRM,3)
          AND TRX = RIGHT('0000'+@TRAN,4) 
          AND CODIGO IN (SELECT CODIGO FROM VST_DEPTO_HISTORICO
                         WHERE FECHA_POS = @FECHA AND ALMACEN_POS = @ALMACEN AND TERM = RIGHT('0000'+@TRM,3) AND TRX = RIGHT('0000'+@TRAN,4)          
                         GROUP BY CODIGO
                         HAVING SUM(CANTIDAD) > 0 )
--
-- Tabla de notas para articulos propios:
SELECT NRO_LINEAS = COUNT(1), 
       CASE WHEN LEFT(INDICAT3,1) <> 4 THEN SUM(TOTAL_BRUTO) ELSE 0 END VALORTOTAL_TOTAL_BRUTO,
       CASE WHEN LEFT(INDICAT3,1) <> 4 THEN SUM(TOTAL_DESCUENTO) ELSE 0 END VALORTOTAL_DESCUENTOS,
       CASE WHEN LEFT(INDICAT3,1) <> 4 THEN SUM(TOTAL_BRUTO) - SUM(TOTAL_DESCUENTO) ELSE 0 END VALORTOTAL_SUBTOTAL, 
       CASE WHEN LEFT(INDICAT3,1) <> 4 THEN ROUND(SUM(IVA), 2) ELSE 0 END VALORTOTAL_IVA,
       CASE WHEN LEFT(INDICAT3,1) <> 4 THEN ROUND(SUM(TOTAL_BRUTO) - SUM(TOTAL_DESCUENTO) + SUM(IVA), 2) ELSE 0 END VALORTOTAL_TOTAL_A_PAGAR,
       CASE WHEN LEFT(INDICAT3,1) <> 4 THEN ROUND(SUM(NETO), 2) ELSE 0 END VALORTOTAL_BASE_TOTAL,
       CASE WHEN LEFT(INDICAT3,1) <> 4 THEN ROUND(SUM(NETO * (CASE
                                                                WHEN (IVA <> 0) THEN 1
                                                                WHEN (RIGHT(INDICAT3,1) = 9) THEN 1 
                                                                ELSE 0 
                                                              END)), 2)
       ELSE 0 
       END VALORTOTAL_BASE_GBLE
INTO #TMP_VTADPT_PRO
FROM #TMP_VTADPT_DET
GROUP BY LEFT(INDICAT3,1)
--
-- Tabla de notas para articulos propios:
SELECT NRO_LINEAS = COUNT(1), 
       CASE WHEN LEFT(INDICAT3,1) = 4 THEN SUM(TOTAL_BRUTO) ELSE 0 END VALORTOTAL_TOTAL_BRUTO,
       CASE WHEN LEFT(INDICAT3,1) = 4 THEN SUM(TOTAL_DESCUENTO) ELSE 0 END VALORTOTAL_DESCUENTOS,
       CASE WHEN LEFT(INDICAT3,1) = 4 THEN SUM(TOTAL_BRUTO) - SUM(TOTAL_DESCUENTO) ELSE 0 END VALORTOTAL_SUBTOTAL, 
       CASE WHEN LEFT(INDICAT3,1) = 4 THEN ROUND(SUM(IVA), 2) ELSE 0 END VALORTOTAL_IVA,
       CASE WHEN LEFT(INDICAT3,1) = 4 THEN ROUND(SUM(TOTAL_BRUTO) - SUM(TOTAL_DESCUENTO) + SUM(IVA), 2) ELSE 0 END VALORTOTAL_TOTAL_A_PAGAR,
       CASE WHEN LEFT(INDICAT3,1) = 4 THEN ROUND(SUM(NETO), 2) ELSE 0 END VALORTOTAL_BASE_TOTAL,
       CASE WHEN LEFT(INDICAT3,1) = 4 THEN ROUND(SUM(NETO * (CASE
                                                                WHEN (IVA <> 0) THEN 1
                                                                WHEN (RIGHT(INDICAT3,1) = 9) THEN 1 
                                                                ELSE 0 
                                                              END)), 2)
       ELSE 0 
       END VALORTOTAL_BASE_GBLE
INTO #TMP_VTADPT_MND
FROM #TMP_VTADPT_DET
GROUP BY LEFT(INDICAT3,1)
--
-- Tabla para el encabezado:
SELECT IDTransaccionM = (RIGHT(FECHA_POS, 6) +RIGHT(TERMINAL, 3)+ TRANSACCION + ALMACEN_POS)
     , VentaNetoM   = ROUND(SUM(VALOR),0)
     , CLIENTE = SUBSTRING(NUMERO_CLIENTE,PATINDEX('%[^0]%',NUMERO_CLIENTE+'.'),LEN(NUMERO_CLIENTE))
     , TERMINAL
     , FECHA = SUBSTRING(FECHA_POS,1,4)  + '-' + SUBSTRING(FECHA_POS,5,2) + '-' + SUBSTRING(FECHA_POS,7,2)
     , HORA = SUBSTRING(HORA_POS,1,2) + ':' + SUBSTRING(HORA_POS,3,2) + ':00-05:00'
     , DCTO_GASTO = ROUND (SUM(CASE WHEN MEDIO_PAGO IN (81, 82, 84) THEN VALOR ELSE 0 END), 0)
     , AJUSTE_CAMBIO = ROUND (SUM(CASE WHEN MEDIO_PAGO = 83 THEN VALOR ELSE 0 END), 0)
     , MAX(CUOTAS) CUOTAS
INTO #TMP_VTAMP
FROM INFORMESPOS.dbo.VST_MP_HISTORICO_SIGNO O
         WHERE FECHA_POS = @FECHA
             AND ALMACEN_POS = @ALMACEN
             AND TERMINAL = RIGHT('0000'+@TRM,4)
             AND TRANSACCION = RIGHT('0000'+@TRAN,4)
         GROUP BY(RIGHT(FECHA_POS, 6) +RIGHT(TERMINAL, 3)+ TRANSACCION + ALMACEN_POS)
              , FECHA_HORA
              , ALMACEN_POS
              , TERMINAL
              , TRANSACCION
              , SUBSTRING(NUMERO_CLIENTE,PATINDEX('%[^0]%',NUMERO_CLIENTE+'.'),LEN(NUMERO_CLIENTE))
              , SUBSTRING(FECHA_POS,1,4)  + '-' + SUBSTRING(FECHA_POS,5,2) + '-' + SUBSTRING(FECHA_POS,7,2)
              , SUBSTRING(HORA_POS,1,2) + ':' + SUBSTRING(HORA_POS,3,2) + ':00-05:00'
--
-- Tabla para el detalle de los medios de pago:
SELECT MEDIO_PAGO
     , SUM(VALOR) SUMA
     , FECHA = SUBSTRING(FECHA_POS,1,4)  + '-' + SUBSTRING(FECHA_POS,5,2) + '-' + SUBSTRING(FECHA_POS,7,2)
     , MP_NOMBRE = DESCRIPCION
     , ROW_NUMBER() OVER(ORDER BY MEDIO_PAGO) AS 'RowNumber'
INTO #TMP_VTAMP_DET
FROM INFORMESPOS.dbo.VST_MP_HISTORICO_SIGNO O
INNER JOIN MEDIOS_DE_PAGO N ON O.MEDIO_PAGO = N.TIPOVARIEDAD
         WHERE FECHA_POS = @FECHA
             AND ALMACEN_POS = @ALMACEN
             AND TERMINAL = RIGHT('0000'+@TRM,4)
             AND TRANSACCION = RIGHT('0000'+@TRAN,4)
             AND MEDIO_PAGO NOT IN (81, 82, 83, 84)
GROUP BY MEDIO_PAGO,SUBSTRING(FECHA_POS,1,4)  + '-' + SUBSTRING(FECHA_POS,5,2) + '-' + SUBSTRING(FECHA_POS,7,2),DESCRIPCION
--
-- Tabla lineal con los medios de pago:
SELECT
   MEDIO_PAGO + ','
   + CAST(RowNumber AS VARCHAR(4)) + ','
   + FECHA + ','
   + MP_NOMBRE
   AS DETALLE_MP
INTO #TMP_VTAMP_DET_MP
FROM #TMP_VTAMP_DET
--
-- Tabla con las tarifas de impuestos:
SELECT TotalBase = ROUND(SUM(NETO),0)
     , TotalIVA = ROUND(SUM(IVA),0)
     , PORCENTAJE 
INTO #TMP_VTAIVA_DET
FROM #TMP_VTADPT_DET
GROUP BY PORCENTAJE
--
-- Tabla lineal con las tarifas de impuestos:
SELECT
     'COP,'
   + LTRIM(STR(TotalBase, 10, 2)) + ','
   + 'COP,'
   + LTRIM(STR(TotalIVA, 10, 2)) + ','
   + '01,IVA,'
   + LTRIM(STR(PORCENTAJE, 10, 2))
   + ',,,,' -- Unos campos vacios que no tengo idea
   AS DETALLE_IMPTO
INTO #TMP_VTAIVA_LINEAL
FROM #TMP_VTAIVA_DET
--
-- Tabla para el detalle de articulos propios:
SELECT 
   '0,' -- Tipo: Propio
   + CAST(RowNumber AS VARCHAR(4)) + ',' -- Posicion
   + LTRIM(STR(CANTIDAD, 10, 2)) + ',' 
   + 'COP,' -- monedaValorBruto
   + LTRIM(STR(NETO, 10, 2)) + ',' -- valorBruto
   + 'COP,' -- monedaTotalImpuestos
   + LTRIM(STR(ROUND(IVA, 0), 10, 2)) + ',' -- valorTotalImpuestos
   + 'COP,' -- monedaRedondeoTotal
   + '0.00,' -- valorRedondeoTotal
   + CODIGO + ','
   + DESCRIPCION + ','
   + 'COP,' -- monedaPrecio
   + LTRIM(STR(TOTAL_BRUTO, 10, 2)) + ',' -- valorPrecio
   + 'ZZ,' -- codigoUnidad de medida
   + LTRIM(STR(CANTIDAD, 10, 2)) + ','
   + LTRIM(STR(ROUND(PRECIO - DESCUENTO - IVA, 0), 10, 2)) + ',' -- Subtotal
   + LTRIM(STR(ROUND(NETO + IVA, 0), 10, 2)) + ',' -- Subotal con impuestos
   + '0.00,' -- Mandato Subtotal
   + '0.00,' -- Mandato Subtotal con impuestos
   + 'COP~' -- monedaBase
   + LTRIM(STR(ROUND(NETO, 0), 10, 2)) + '~' -- valorBase
   + 'COP~' -- monedaImpuesto
   + LTRIM(STR(ROUND(IVA, 0), 10, 2)) + '~' -- valorImpuesto
   + CASE WHEN CODIGO = @IMPT_BOLSA THEN '22~' ELSE '01~' END-- codigoImpuesto
   + CASE WHEN CODIGO = @IMPT_BOLSA THEN 'INC Bolsas~' ELSE 'IVA~' END-- nombreImpuesto
   + LTRIM(STR(ROUND(PORCENTAJE, 0), 10, 2)) + '~' -- porcentajeImpuesto
   + CASE WHEN CODIGO = @IMPT_BOLSA THEN '94~' ELSE '~' END -- codigoBolsas
   + CASE WHEN CODIGO = @IMPT_BOLSA THEN LTRIM(STR(CANTIDAD, 10, 2)) + '~' ELSE '~' END -- cantidadBolsas
   + CASE WHEN CODIGO = @IMPT_BOLSA THEN 'COP~' ELSE '~' END -- monedaValorBolsas
   + CASE WHEN CODIGO = @IMPT_BOLSA THEN LTRIM(STR(PRECIO, 10, 2)) + ',' ELSE ',' END -- valor (Bolsas)
   + 'COP~' -- monedaValorDescuento
   + LTRIM(STR(TOTAL_DESCUENTO, 10, 2)) + '~' --valor (descuento)
   + 'COP~' -- monedaBase
   + LTRIM(STR(TOTAL_BRUTO, 10, 2)) + '~' -- valorBase
   + '1~' -- consecutivo
   + 'false~' -- esCargo
   + 'Descuento producto~' -- consecutivo
   + LTRIM(STR(ROUND(TOTAL_DESCUENTO / TOTAL_BRUTO * 100.0, 2), 10, 2)) + '~' -- porcentaje de descuento
   + '9999DCTO01' 
   + ',,'
   AS DETALLE_PRO
INTO #TMP_VTADPT_DET_PRO
FROM #TMP_VTADPT_DET
WHERE LEFT(INDICAT3,1) <> 4
--
-- Tabla para el detalle de articulos de terceros:
-- ???????????? FALTA ???????????????
--
-- Tabla para el ajuste al cambio:
SELECT TOP 1 LTRIM(STR(VALOR,10,2)) VALOR
     , ',' + T.CONSECUTIVO
     + ',' + T.ESCARGO -- es cargo?
     + ',' +  T.DESCRIPCION -- Consecutivo registro
     + ',' + LTRIM(STR(T.PORCENTAJE, 10, 2))
     + ',' + T.ID -- ID ficticio
     AS AJUSTE_CAMBIO
INTO #TMP_BONO_CAMBIO
FROM
(
    SELECT '0' VALOR
         , 'BONO POR CAMBIO' DESCRIPCION
         , '02' CONSECUTIVO
         , 'false' ESCARGO
         , '0' PORCENTAJE
         , LTRIM(STR(DP.VALORTOTAL_TOTAL_BRUTO + DM.VALORTOTAL_TOTAL_BRUTO, 10, 2)) TOTAL_BRUTO
         , '01' ID 
    FROM #TMP_VTADPT_PRO DP, #TMP_VTADPT_MND DM
    UNION
    SELECT VALOR
         , 'BONO POR CAMBIO' DESCRIPCION
         , '02' CONSECUTIVO
         , 'false' ESCARGO
         , LTRIM(STR(ROUND(VALOR / (DP.VALORTOTAL_TOTAL_BRUTO + DM.VALORTOTAL_TOTAL_BRUTO) * 100.0, 0),10, 2)) PORCENTAJE
         , LTRIM(STR(DP.VALORTOTAL_TOTAL_BRUTO + DM.VALORTOTAL_TOTAL_BRUTO, 10, 2)) TOTAL_BRUTO
         , '01' ID 
    FROM VST_MP_HISTORICO_SIGNO, #TMP_VTADPT_PRO DP, #TMP_VTADPT_MND DM
    WHERE FECHA_POS = @FECHA
        AND ALMACEN_POS = @ALMACEN
        AND TERMINAL = RIGHT('0000'+@TRM,4)
        AND TRANSACCION = RIGHT('0000'+@TRAN,4)
        AND MEDIO_PAGO = 83
) T
ORDER BY VALOR DESC
--
-- Tabla para el descuento al gasto:
SELECT TOP 1 LTRIM(STR(VALOR,10,2)) VALOR
     , ',' + T.CONSECUTIVO
     + ',' + T.ESCARGO -- es cargo?
     + ',' +  T.DESCRIPCION -- Consecutivo registro
     + ',' + LTRIM(STR(T.PORCENTAJE, 10, 2))
     + ',' + T.ID -- ID ficticio
     AS DCTO_GASTO
INTO #TMP_DCTO_GASTO
FROM
(
    SELECT '0' VALOR
         , 'DESCUENTOS AL GASTO' DESCRIPCION
         , '1' CONSECUTIVO
         , 'false' ESCARGO
         , '0' PORCENTAJE
         , LTRIM(STR(DP.VALORTOTAL_TOTAL_BRUTO + DM.VALORTOTAL_TOTAL_BRUTO, 10, 2)) TOTAL_BRUTO
         , '01' ID 
    FROM #TMP_VTADPT_PRO DP, #TMP_VTADPT_MND DM
    UNION
    SELECT VALOR
         , 'DESCUENTOS AL GASTO' DESCRIPCION
         , '1' CONSECUTIVO
         , 'false' ESCARGO
         , LTRIM(STR(ROUND(VALOR / (DP.VALORTOTAL_TOTAL_BRUTO + DM.VALORTOTAL_TOTAL_BRUTO) * 100.0, 0),10, 2)) PORCENTAJE
         , LTRIM(STR(DP.VALORTOTAL_TOTAL_BRUTO + DM.VALORTOTAL_TOTAL_BRUTO, 10, 2)) TOTAL_BRUTO
         , '01' ID 
    FROM VST_MP_HISTORICO_SIGNO, #TMP_VTADPT_PRO DP, #TMP_VTADPT_MND DM
    WHERE FECHA_POS = @FECHA
        AND ALMACEN_POS = @ALMACEN
        AND TERMINAL = RIGHT('0000'+@TRM,4)
        AND TRANSACCION = RIGHT('0000'+@TRAN,4)
        AND MEDIO_PAGO IN (81, 82, 84)
) T
ORDER BY VALOR DESC
--
-- Tabla para el consecutivo fiscal
SELECT RIGHT(CONSECUTIVO_FISCAL,7) CONSECUTIVO
	, PREFIJO
	, RESOLUCION
	, FECHA_INI
	, FECHA_FIN
	, RANGO_INI
	, RANGO_FIN
INTO #TMP_FISCAL
FROM CONSEFISNEW_ALL
WHERE FECHA_POS       = @FECHA
  AND ALMACEN_POS     = @ALMACEN
  AND NRO_TERMINAL    = RIGHT('0000'+@TRM,4)
  AND NRO_TRANSACCION = RIGHT('0000'+@TRAN,4)
--
-- Tabla para el almacen
SELECT *
INTO #TMP_ALMACEN
FROM ALMACENESNEW
WHERE NUMERO = RIGHT('0000'+@ALMACEN,3)
--
-- La consulta final:
SELECT
     '1|' + A.NUMERO + '|' 
     + CASE WHEN M.CLIENTE = '999999999999' THEN '222222222222' ELSE M.CLIENTE END + '|' -- Cliente
     + CASE WHEN (SELECT SUM(VALORTOTAL_TOTAL_BRUTO) FROM #TMP_VTADPT_MND) > 0 THEN '11' ELSE '10' END -- 10 para trx normal, 11 cuando incluye mandado
     + '|' 
     + CASE WHEN A.PREFIJO = 'SE' THEN '2' ELSE '1' END -- 2 para preubas, 1 para produccion
     + '|' 
     + F.PREFIJO 
     --+ CASE WHEN A.PREFIJO = 'SE' THEN 'TT' ELSE M.TERMINAL END -- TT para pruebas
     + F.CONSECUTIVO + '|' 
     + M.FECHA + '|'
     + M.HORA + '|'
     + LTRIM(STR(DP.NRO_LINEAS,4,0)) + '|' -- Contador lineas de la trx
     + 'AUTORIZACION DE FACTURACION~SEGUN FORMULARIO No.' + F.RESOLUCION  -- resolucionNotes, RESOLUCION
     + '~RANGO ' + F.PREFIJO + RIGHT('00000' + F.RANGO_INI, 7) + ' - '   -- resolucionNotes, RANGO FINAL
     + F.PREFIJO + RIGHT('00000' + F.RANGO_FIN,7)  -- resolucionNotes, RANGO FINAL
     + '~VIGENCIA: ' + F.FECHA_INI + ' HASTA ' + F.FECHA_FIN + '|' -- resolucionNotes, FECHAS
     + CONVERT(VARCHAR,CONVERT(INT, M.CUOTAS)) -- plazo del credito
     + '|||' -- campos vacios
     + LTRIM(STR(DP.VALORTOTAL_TOTAL_BRUTO, 10, 2)) + '|'
     + LTRIM(STR(DP.VALORTOTAL_DESCUENTOS, 10, 2)) + '|'
     + LTRIM(STR(DP.VALORTOTAL_SUBTOTAL, 10, 2)) + '|'
     + LTRIM(STR(DP.VALORTOTAL_IVA, 10, 2)) + '|'
     + LTRIM(STR(DP.VALORTOTAL_TOTAL_A_PAGAR, 10, 2)) + '|'
     + '0.00|0.00|' -- campos vacios
     + LTRIM(STR(DM.VALORTOTAL_TOTAL_BRUTO, 10, 2)) + '|'
     + LTRIM(STR(DM.VALORTOTAL_DESCUENTOS, 10, 2)) + '|'
     + LTRIM(STR(DM.VALORTOTAL_SUBTOTAL, 10, 2)) + '|'
     + LTRIM(STR(DM.VALORTOTAL_IVA, 10, 2)) + '|'
     + LTRIM(STR(DM.VALORTOTAL_TOTAL_A_PAGAR, 10, 2)) + '|'
     + M.FECHA + '|'
     + '00:01:00-05:00|'
     + M.FECHA + '|'
     + '23:59:59-05:00|'
     + F.PREFIJO  
     --+ CASE WHEN A.PREFIJO = 'SE' THEN 'TT' ELSE M.TERMINAL END -- TT para pruebas
     + '|COP|' -- Moneda del total del IVA
     + LTRIM(STR((DP.VALORTOTAL_IVA + DM.VALORTOTAL_IVA), 10, 2))  + '|' -- IVA total
     + 'COP|0.00|' -- Moneda y Redondeo del calculo del IVA
     + 'COP|' -- Moneda de sumatoria del valor de los articulos
     + LTRIM(STR((DP.VALORTOTAL_TOTAL_A_PAGAR + DM.VALORTOTAL_TOTAL_A_PAGAR), 10, 2))  + '|' -- Subtotal articulos
     + 'COP|' -- Moneda de sumatoria de la base imponible total
     + LTRIM(STR((DP.VALORTOTAL_BASE_GBLE + DM.VALORTOTAL_BASE_GBLE), 10, 2)) + '|' -- sumatoria de la base imponible total
     + 'COP|' -- Moneda de sumatoria del total bruto
     + LTRIM(STR((DP.VALORTOTAL_BASE_TOTAL + DM.VALORTOTAL_BASE_TOTAL), 10, 2)) + '|' -- sumatoria del total bruto
     + 'COP|' -- Moneda de total a pagar
     + LTRIM(STR((DP.VALORTOTAL_TOTAL_A_PAGAR + DM.VALORTOTAL_TOTAL_A_PAGAR - M.DCTO_GASTO - M.AJUSTE_CAMBIO), 10, 2)) + '|' -- Total a pagar
     + 'COP|' -- Moneda para la factura
     + (SELECT STUFF((SELECT ';' + DETALLE_PRO FROM #TMP_VTADPT_DET_PRO FOR XML PATH('')), 1,1,'')) -- Detalle de productos propios
     + '|'
     + (SELECT STUFF((SELECT ';' + DETALLE_MP FROM #TMP_VTAMP_DET_MP FOR XML PATH('')), 1,1,'')) -- Detalle de medios de pago
     + '|'
     + (SELECT STUFF((SELECT ';' + DETALLE_IMPTO FROM #TMP_VTAIVA_LINEAL FOR XML PATH('')), 1,1,'')) -- Detalle de los impuestos
     + '|'
     + 'COP,' -- Moneda del DESCUENTO AL GASTO
     + G.VALOR + ',' 
     + 'COP,' -- Moneda del valor de la base de la trx
     + LTRIM(STR((DP.VALORTOTAL_TOTAL_BRUTO + DM.VALORTOTAL_TOTAL_BRUTO), 10, 2)) -- Base para calcular porcentaje
     + G.DCTO_GASTO
     + ';'
     + 'COP,' -- Moneda del BONO POR CAMBIO
     + B.VALOR + ',' 
     + 'COP,' -- Moneda del valor de la base de la trx
     + LTRIM(STR((DP.VALORTOTAL_TOTAL_BRUTO + DM.VALORTOTAL_TOTAL_BRUTO), 10, 2)) -- Base para calcular porcentaje
     + B.AJUSTE_CAMBIO
     + '|'
     + 'COP|' -- Moneda Redondeo Descuentos
     + '0.00|' -- valor Redondeo Descuentos
     + 'COP|' -- Moneda Descuento Gasto
     + G.VALOR + '|' -- valor Descuento Gasto  ???
     + @TRM + '|' -- id Terminal
     + @TRAN + '|' -- id Transaccion POS
     + G.VALOR + '|' -- Otros descuentos ???
     + '01' -- Proceso ???
FROM
     #TMP_VTADPT_PRO DP,
     #TMP_VTADPT_MND DM,
     #TMP_VTAMP M,
     #TMP_FISCAL F,
     #TMP_ALMACEN A,
     #TMP_BONO_CAMBIO B,
     #TMP_DCTO_GASTO G
/**
SELECT * FROM #TMP_VTADPT_PRO DP
SELECT * FROM #TMP_VTADPT_MND DM
SELECT * FROM #TMP_VTAMP M
SELECT * FROM #TMP_VTAMP_DET_MP MD
SELECT * FROM #TMP_FISCAL F
SELECT * FROM #TMP_VTADPT_DET
SELECT * FROM #TMP_VTAIVA_DET
SELECT * FROM #TMP_VTAIVA_LINEAL
SELECT * FROM #TMP_DCTO_GASTO
SELECT * FROM #TMP_ALMACEN A
**/

DECLARE 
      @URI VARCHAR(300)
    , @HTTP_METHOD VARCHAR(50)
    , @REQUEST_BODY VARCHAR(MAX)
    , @HTTP_RESPONSE VARCHAR(MAX)
    , @Object AS INT;
SET @URI = 'http://172.16.8.201:8280/invoice/contigencia';    -- Pruebas
SET @HTTP_METHOD    = 'POST';
SET @REQUEST_BODY = '1|017|900713252|10|1|1700110000736|2022-12-03|17:23:00-05:00|1|AUTORIZACION DE FACTURACION~SEGUN FORMULARIO No.18764039815395~RANGO 17810000001 - 17810900000~VIGENCIA: 20221118 HASTA 20240518|0|||604957.98|96611.76|508346.22|96585.78|604932.00|0.00|0.00|0.00|0.00|0.00|0.00|0.00|2022-12-03|00:01:00-05:00|2022-12-03|23:59:59-05:00|170011|COP|96585.78|COP|0.00|COP|604932.00|COP|508346.22|COP|508346.22|COP|604932.00|COP|0,1,1.00,COP,508346.22,COP,96586.00,COP,0.00,770519104238, ITEM 770519104238,COP,604957.98,ZZ,1.00,508346.00,604932.00,0.00,0.00,COP~508346.00~COP~96586.00~01~IVA~19.00~~~~,COP~96611.76~COP~604957.98~1~false~Descuento producto~16.00~9999DCTO01,,|31,1,2022-12-03,Tarjeta Débito Maestro|COP,508346.00,COP,96586.00,01,IVA,19.00,,,,|COP,0.00,COP,604957.98,1,false,DESCUENTOS AL GASTO,0.00,01;COP,0.00,COP,604957.98,02,false,BONO POR CAMBIO,0.00,01|COP|0.00|COP|0.00|11|37|0.00|01'
DECLARE @LEN INT = LEN(@REQUEST_BODY)
-- Consumiendo WS para generar XML:
EXEC sp_OACreate 'MSXML2.XMLHTTP', @Object OUT; 
EXEC sp_OAMethod @Object, 'open', NULL, @HTTP_METHOD, @URI, 'false' 
EXEC sp_OAMethod @Object, 'setRequestHeader', NULL, 'Content-Type', 'text/plain'
EXEC sp_OAMethod @Object, 'setRequestHeader', NULL, 'Content-Length', @LEN
EXEC sp_OAMethod @Object, 'send', NULL, @REQUEST_BODY 
EXEC sp_OAGetProperty @Object, 'responseText', @HTTP_RESPONSE OUT 
EXEC sp_OADestroy @Object  
SELECT @HTTP_RESPONSE;