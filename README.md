3. Subasta (English o Dutch Auction)
Contrato de subasta con tiempo límite.
Practicas:
* Manejo de tiempo (block.timestamp, vm.warp)
* Reembolsos seguros
* Prevención de reentrancy
Extras:
* Encuentra y documenta vulnerabilidades
* Escribe tests que rompan tu propio contrato

## 1) English Auction (recomendada)

### Objetivo

Subastar un NFT (o un “item” abstracto) durante un tiempo. Gana la mayor puja. Los que pierden pueden **withdraw** su dinero (pull payments).

---

## Funciones que debería tener

### A) Setup / estado

* `constructor(address seller, uint256 duration, uint256 reservePrice)`
  (o que `seller = msg.sender`)

Variables típicas:

* `address public seller`
* `uint256 public endAt`
* `uint256 public highestBid`
* `address public highestBidder`
* `bool public started`
* `bool public ended`
* `mapping(address => uint256) public pendingReturns` (reembolsos)

Opcional (si subastas NFT):

* `IERC721 public nft; uint256 public tokenId;`

---

### B) Control del ciclo de vida

1. **start()**

* Solo seller
* Marca `started = true`
* Define `endAt = block.timestamp + duration`
* (Si NFT) transfiere el NFT al contrato

2. **bid() payable**

* Requiere `started` y `block.timestamp < endAt`
* Requiere `msg.value > highestBid` (y quizá `>= reserve`)
* Si ya había highestBidder, su bid anterior pasa a `pendingReturns[prevHighest] += prevHighestBid`
* Actualiza `highestBidder/highestBid`
* Emite `BidPlaced(bidder, amount)`

3. **withdraw()**

* Permite a cualquiera retirar su `pendingReturns[msg.sender]`
* Pone a 0 antes de enviar (CEI)
* Emite `Withdraw(bidder, amount)`

4. **end()**

* Requiere `started` y `block.timestamp >= endAt`
* Requiere `!ended`
* Marca `ended = true`
* Si `highestBid >= reservePrice`:

  * transfiere el pago al seller (o lo deja claimable)
  * (si NFT) transfiere NFT al ganador
* Si no llegó al reserve:

  * (si NFT) devuelve NFT al seller
  * el highestBidder debe poder retirar su bid (pendingReturns)

Eventos:

* `AuctionStarted(endAt)`
* `BidPlaced(bidder, amount)`
* `AuctionEnded(winner, amount)`
* `Withdraw(bidder, amount)`

---

## Detalles de seguridad importantes (que deberías implementar)

* **Pull over push payments**: no devuelvas ETH directo en `bid()`, acumúlalo en `pendingReturns`.
* `nonReentrant` en `withdraw()` (y quizá en `end()`)
* Chequeos de tiempo con `vm.warp` en tests
* No permitir `bid()` después del final
* No permitir `end()` antes de tiempo
* Manejar reserve price correctamente

---

# 2) Tests que deberías hacer (Foundry)

## A) Tests de “ciclo feliz”

1. `start()` por seller funciona y setea `endAt`
2. Bid 1 (Alice) se convierte en highest
3. Bid 2 (Bob) mayor reemplaza a Alice
4. Alice puede `withdraw()` su bid anterior
5. Pasas el tiempo y `end()`:

   * gana Bob
   * seller recibe `highestBid`
   * (si NFT) Bob recibe NFT

---

## B) Tests de reverts (muy importantes)

6. `start()` por no-seller revierte
7. `bid()` antes de start revierte
8. `bid()` con amount <= highestBid revierte
9. `bid()` después de endAt revierte (`vm.warp`)
10. `end()` antes de tiempo revierte
11. `end()` 2 veces revierte

---

## C) Reserve price

12. Si `highestBid < reserve` al final:

* no hay winner real
* seller recupera NFT (si aplica)
* highestBidder puede retirar su bid (vía `withdraw`)

---

## D) Attack tests (nivel auditor)

13. **Reentrancy en withdraw**

* Contrato atacante que recibe ETH y reentra en `withdraw()`
* Debe fallar por CEI y/o `nonReentrant`

14. **DoS por fallback revert (si hicieras push payments)**

* Esto es un test educativo: demuestra por qué no haces refund directo en `bid()`
* (Si lo implementas mal, un bidder con fallback que revierte bloquea la subasta)

---

## E) Fuzz / invariants (bonus)

15. Fuzz: el highestBid siempre es el máximo de las bids vistas
16. Invariant: `address(this).balance == highestBid + sum(pendingReturns)`
    (muy bonita para auditoría)
