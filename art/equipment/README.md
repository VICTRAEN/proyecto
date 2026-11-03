# Iconos de objetos equipables

Cada objeto tiene su icono en `art/equipment/<id>.png` (el `id` es el nombre de su JSON en
`data/equipment/`, y la ruta esta en su campo `"icon"`).

Los PNG actuales son PLACEHOLDERS generados (marco del color de la rareza + iniciales):
cada objeto tiene el suyo, ninguno reutiliza el de otro.

Para poner el icono definitivo: sustituye el PNG con el MISMO nombre (256x256 o mayor,
cuadrado, fondo transparente). No hay que tocar codigo ni JSON. Si un archivo falta, la
pantalla dibuja un recuadro de reserva con la rareza, asi que nunca se rompe.

Un objeto nuevo = un JSON en `data/equipment/` + su PNG aqui.
