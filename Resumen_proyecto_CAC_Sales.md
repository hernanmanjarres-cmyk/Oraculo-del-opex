# Proyecto CAC Sales — Resumen del trabajo

> Construcción de la tabla de costos de activación (CAC) para el equipo de Sales, a partir de las fuentes de Metabase y el archivo original `OPEX_calculadora_payback`.
> Fecha: Abril 2026

---

## 1. Contexto y punto de partida

El equipo de Sales necesitaba un referente de costos CAC por municipio, tipo de medida y operador de red para cotizar activaciones. El archivo original `OPEX_calculadora_payback` servía como primera aproximación pero tenía varios problemas estructurales que habría generado malas cotizaciones:

- La columna `plus` no era mano de obra pura como se asumía: aplicaba un factor oculto de ×1.515 sobre el costo total (margen del 51.5% no documentado).
- Faltaba separar COSTA del Interior: la media simple de Indirecta mezclaba geografías no comparables (COSTA ≈ 2× Interior por carro canasta y descargos).
- Registros con n≤3 actividades no eran estadísticamente representativos (43% de los grupos).
- Datos corruptos sin marcar: SUCRE Indirecta $46k con n=2 por error de tipificación.
- Outliers sin flag (LORICA $11.4M, APARTADÓ $5.3M) distorsionaban los promedios.
- Municipios sin departamento completado pese a que era derivable de Hoja 5.
- 7 municipios mal asignados a departamento por nombres homónimos.

---

## 2. Decisiones metodológicas acordadas

| Decisión | Valor |
|---|---|
| Concepto de costo para Sales | Costo total + margen explícito editable |
| Factor de margen default | **×1.30** (celda `Parámetros!B5`, editable) |
| Estadístico base | **Media ponderada por # actividades** (desde Data x dpto Metabase) |
| Segmentación geográfica | **3 zonas**: COSTA, CENTRO, Interior |
| Criterio de piso por zona | **MAX(piso nacional, P50 de deptos robustos n≥10)** |
| Monotonicidad | **D ≤ S ≤ I** forzada en todo municipio |
| Transporte BIA | Aplicado a TODOS los municipios = `km (ida+vuelta) × $2.000 × 2 viajes` |
| Descargos en Directa | **$0 en todas las zonas** (regla absoluta) |
| Descargos en Semi/Indirecta | Media histórica del depto cuando >50% de ciudades lo cobran |
| Acompañamiento default | **$360.000** |

### Zonas definidas

- **COSTA**: Atlántico, Bolívar, Cesar, Córdoba, La Guajira, Magdalena, Sucre
- **CENTRO**: Cundinamarca + Bogotá D.C. (separada del Interior porque el volumen Bogotá sesga los promedios)
- **Interior**: resto del país

### Pisos finales (P50) por zona × tipo

| Zona | Directa | Semidirecta | Indirecta |
|---|---|---|---|
| COSTA | $660.467 | $792.560 | **$3.246.382** |
| CENTRO | $300.000 | $500.000 | $1.200.000 |
| Interior | $796.686 | $956.023 | $1.848.030 |

---

## 3. Correcciones de datos aplicadas

### Factor `plus` oculto eliminado
El ×1.515 del archivo original quedó fuera. Se sustituyó por margen **explícito y editable** en `Parámetros!B5`.

### 7 municipios reasignados al departamento correcto (según código DANE)

| Municipio | Antes (mal) | Ahora (según DANE) | Zona nueva |
|---|---|---|---|
| Sabanalarga (8638) | Antioquia | **Atlántico** | COSTA |
| Candelaria (8141) | Valle del Cauca | **Atlántico** | COSTA |
| Villanueva (13873) | La Guajira | **Bolívar** | COSTA |
| Granada (5313) | Meta | **Antioquia** | Interior |
| Caldas (5129) | Caldas (depto) | **Antioquia** | Interior |
| Albania (18029) | Santander | **Caquetá** | Interior |
| Restrepo (50606) | Valle del Cauca | **Meta** | Interior |

Trazabilidad: en la columna `Fuente` de cada fila corregida aparece el comentario `[CORREGIDO por DANE: ...]`.

### Outliers identificados y marcados
Dentro del percentil Q3 + 1.5·IQR por tipo de medida: LORICA, SOLEDAD, APARTADÓ, HISPANIA, LA ESTRELLA, LA PLATA. Se mantuvieron en la data con flag (⚠) para cotización conservadora.

---

## 4. Estructura final del archivo

El archivo `CAC_Sales_validado.xlsx` quedó con 11 hojas organizadas de más útil a más técnica:

### Hoja 1 — Cotizador (la principal para Sales)
Herramienta interactiva. Sales escribe tres datos en desplegables:
1. **Ciudad** (lista de 205)
2. **Operador de Red** (lista de 21)
3. **Tipo de medida** (Directa / Semidirecta / Indirecta)

Devuelve automáticamente:
- Precio total a cotizar (rojo grande)
- Desglose: costo base, transporte BIA, acompañamiento, descargos
- Metadatos: Zona, Departamento, Código DANE, Fuente, Nivel de confianza (ALTA/MEDIA/BAJA)

Si la combinación Ciudad+OR+Tipo no existe, retorna `"Combinación no disponible"`.

### Hoja 2 — Instrucciones Sales
Guía operativa en tres métodos según cuánto sabe Sales del cliente:
- **Método 1**: Conoce Ciudad + OR + Tipo → usa Cotizador
- **Método 2**: Conoce solo Depto → usa `CAC por Depto` columna conservadora
- **Método 3**: No conoce ni depto → usa `Resumen Nacional` columna conservadora

### Hoja 3 — Parámetros
Factor de margen editable (`B5 = 1.30` default). Cambiando esta celda todo el archivo recalcula.

### Hoja 4 — Pisos aplicados
Tabla con los 9 pisos (3 zonas × 3 tipos) con racional y referencia del cálculo (P50 zona vs piso nacional vs monotonía).

### Hoja 5 — Resumen Nacional
9 filas (3 zonas × 3 tipos) con escenarios **Realista vs Conservador** lado a lado. Para cotización a ciegas.

### Hoja 6 — CAC por OR
Granularidad media: un OR + tipo de medida. Incluye columna Servicio MO pura (sin transporte ni material) para casos donde Sales necesite esa cifra.

### Hoja 7 — CAC por Depto (reconstruida con OR)
**68 filas** con duplicidad para Valle del Cauca (CELSIA + CETSA + EMCALI) y Santander (ESSA + RUITOQUE). Dos escenarios:
- **Realista**: promedio ponderado + acomp + desc
- **Conservador**: actividad pura + transporte P75 km del depto + acomp + desc

### Hoja 8 — Data ampliada por municipio (donde ocurre la magia)
**630 filas** (205 municipios × 3 tipos × duplicidad OR en Cali/Floridablanca/Piedecuesta/Girón/Bucaramanga).

Columnas:
| Col | Contenido |
|---|---|
| A-E | Ciudad, DANE, Depto, Zona, Operador de Red |
| F | Tipo de medida |
| G | AVG costo total (con piso y monotonía aplicados) |
| H | plus = `G × Parámetros!B5` |
| I, J | Acompañamiento, Descargos |
| K | Total = plus + acomp + desc (sin transporte BIA) |
| L | Fuente del dato |
| M | Km ida+vuelta |
| N | Transporte BIA = `M × 2000 × 2` |
| O | **Total con Transporte BIA** = `(G + N) × margen + acomp + desc` |

Colores: verde = histórico real; amarillo = extrapolado; naranja = piso o monotonía aplicada.

### Hojas 9-11 — Referencia técnica
Lookup por Ciudad, Outliers y Excepciones, Diagnóstico vs archivo original.

---

## 5. Duplicidad de OR activada

Basada en cobertura territorial real (no solo en la data de Metabase):

| Municipio(s) | OR asignados | Razón |
|---|---|---|
| Cali | EMCALI + CELSIA_VALLE | EMCALI urbana, CELSIA rural |
| Floridablanca, Piedecuesta, Girón, Bucaramanga | ESSA + RUITOQUE | RUITOQUE como opción comercial |
| Tuluá, San Pedro | CETSA exclusivo | Por concesión histórica |
| Cartago | CELSIA_VALLE | Geográficamente Valle, no Risaralda |
| Santa Rosa de Cabal | CHEC | Es Caldas, no Risaralda |
| Resto (~200 municipios) | OR default del depto | AFINIA, AIRE, EPM, ENEL, etc. |

---

## 6. Validación con Sales

El entregable final se pasó a Sales para ajuste manual. Observaciones del usuario:

- Aplicó ajustes manuales al alza sobre precios que salieron bajos en la tabla.
- Algunos casos que el piso P50 no alcanzó a cubrir se corrigieron en la versión de Sales.
- Los descargos en Directa quedaron en $0 como regla firme.

---

## 7. Hallazgos clave documentados

1. **El factor ×1.515 del archivo original** representaba un margen no declarado que habría hecho sobrecotizar +51.5% sobre el costo real.
2. **El volumen Bogotá distorsiona Cundinamarca e Interior**: el realista de Directa en Cundinamarca salía $217k (sesgado por 886 actividades en Bogotá) pero el conservador queda en $905k (4.17× más). Por eso se aisló como zona CENTRO.
3. **Sincelejo Indirecta** pasaba por absurdo inicialmente ($419k) por un error de tipificación en SUCRE Indirecta n=2. Con piso COSTA P50 quedó en $3.25M, consistente con Atlántico $2.95M, La Guajira $3.25M y Córdoba $4.39M.
4. **El 43% de los grupos depto×tipo tienen menos de 10 actividades**, estadísticamente poco confiables. La columna `Nivel de confianza` (ALTA/MEDIA/BAJA) en el Cotizador refleja esto.
5. **Transporte BIA oculto en el archivo original**: un municipio base como Sincelejo se veía igual que Zona Bananera (214 km de distancia) porque el contratista asumía el transporte en su AVG. Al separarlo como columna visible, el costo real de ejecución BIA queda explícito.

---

## 8. Qué quedó para iteración futura

- **Chocó** solo tiene un municipio (Quibdó) sin data histórica propia — cayó al fallback.
- **Km de los 7 municipios corregidos** conservan los valores de Hoja 5 del archivo original que corresponden al municipio equivocado. Los km deberían recalcularse desde las bases correctas (ej. Sabanalarga Atlántico a 55 km de Barranquilla, no 231 km a Medellín).
- **Descargos por OR específico** (no por depto): si en Valle CETSA cobra distinto que EMCALI, el archivo actual aplica el mismo descargo a los 3 OR del depto.
- **AIRE Atlántico con descargos en $0**: menos del 50% de ciudades de Atlántico tenían descargo histórico registrado. Puede ser ruido en la data o realidad operativa — validar con operaciones.
- **RUITOQUE como OR**: técnicamente es comercializador, no OR (el OR real en Floridablanca es ESSA). Se mantuvo como opción duplicada porque aparece en Metabase, pero vale validar si mantenerlo o colapsarlo con ESSA.

---

## 9. Cómo mantener el archivo en el tiempo

1. **Para cambiar el margen comercial**: editar `Parámetros!B5`. Todo recalcula.
2. **Para agregar nuevos municipios**: añadirlos a Hoja 5 con Municipio, Departamento, km, y DANE, luego re-ejecutar el script de construcción.
3. **Para actualizar CAC cuando Metabase tenga más data**: re-exportar `DATA_UNIFICADA`, `Data x dpto`, `Data x OR` y correr el pipeline completo.
4. **Para ajustar un valor específico manualmente**: editar la celda directamente en `Data ampliada por municipio` (no recomendado porque se pierde la traza de cálculo).

---

## 10. Créditos de fuentes

- `OPEX_calculadora_payback` (archivo original)
- Metabase: query CAC BIA (pregunta 66727)
- Metabase: query Costos asociados a OPEX (pregunta 66793)
- Metabase: Hoja 5 transporte con km por municipio
- Contexto del proyecto CAC OPEX Activación (marzo 2026)
- Información pública de cobertura territorial de operadores de red (Celsia, EMCALI, CETSA, Ruitoque ESP)
- Códigos DANE oficiales para validación de municipios

---

*Documento generado al cierre del proceso de construcción. La versión del archivo entregada a Sales incorpora ajustes manuales adicionales aplicados por el usuario.*
