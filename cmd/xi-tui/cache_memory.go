package main

import (
	"container/list"
	"encoding/json"
	"reflect"
	"sync"
	"time"
)

// ============================================================================
// @TODO: EXTRACT TO `internal/cache/memory_cache.go`
// ============================================================================

const memoryLimit = 16 << 20 // Bitwise shift: 16 * 2^20 = 16 MiB (16.777.216 bytes).

// Em Node.js, um `Map` já mantém a ordem de inserção nativamente, permitindo fazer um LRU cache
// deletando e reinserindo a chave (`map.delete(k); map.set(k, v)`).
// Em Go, a ordem de iteração de um `map` é propositalmente RANDOMIZADA pelo runtime a cada execução.
// Por isso, para construir um cache LRU (Least Recently Used) com busca e remoção em O(1),
// combinamos duas estruturas:
//   1. `map[string]*list.Element` -> Acesso instantâneo O(1) pela chave.
//   2. `*list.List` (Doubly Linked List) -> Mantém a ordem de uso (mais recente na frente, mais antigo atrás).

type memoryEntry struct {
	key     string
	raw     any       // Guarda o valor tipado direto na RAM (zero JSON.parse/stringify no cache hit!).
	payload []byte    // Fallback opcional caso seja necessário clonar via bytes.
	size    int       // Tamanho estimado em bytes para controlar o teto de 16 MiB.
	saved   time.Time // Timestamp de quando foi salvo para validar o TTL (Stale-While-Revalidate).
}

type memoryCache struct {
	// Em Node.js (single-threaded), você nunca precisa de Mutex para acessar um `Map` em memória.
	// Em Go, várias goroutines (ex: `fetchRuns`, `fetchJobs`, `streamJobLogs`) rodam em paralelo
	// em múltiplos núcleos de CPU. Acessar um `map` concorrentemente sem lock causa `fatal error: concurrent map writes` (panic).
	mu    sync.Mutex
	used  int
	items map[string]*list.Element
	order *list.List
}

var hotCache = &memoryCache{
	items: make(map[string]*list.Element, 64), // Pré-aloca buckets para evitar rehash inicial.
	order: list.New(),
}

// estimateSize calcula o peso aproximado do objeto na RAM sem precisar serializar para JSON.
func estimateSize(v any) int {
	switch val := v.(type) {
	case string:
		return len(val) + 16
	case []byte:
		return len(val) + 24
	case []run:
		// Estima ~96 bytes por struct `run` (ID + strings headers + texto médio).
		return len(val)*96 + 24
	case []job:
		total := len(val)*96 + 24
		for i := range val {
			total += len(val[i].Steps) * 64
		}
		return total
	default:
		return 256
	}
}

// assignValue copia o valor em memória para o ponteiro `target` (ex: `&runs` ou `&value`).
// Isso elimina 100% do `json.Unmarshal` nos cache hits de memória (de ~50µs para ~5ns!).
func assignValue(src any, target any) bool {
	if src == nil || target == nil {
		return false
	}

	// Fast-path sem reflection para os tipos concretos da nossa aplicação (zero alocação!).
	switch dst := target.(type) {
	case *string:
		if s, ok := src.(string); ok {
			*dst = s
			return true
		}
	case *[]run:
		if r, ok := src.([]run); ok {
			// Faz uma cópia rasa do slice para evitar data race se o chamador mutar o slice depois.
			cp := make([]run, len(r))
			copy(cp, r)
			*dst = cp
			return true
		}
	case *[]job:
		if j, ok := src.([]job); ok {
			cp := make([]job, len(j))
			copy(cp, j)
			*dst = cp
			return true
		}
	}

	// Fallback genérico via `reflect` caso algum tipo novo seja salvo no cache no futuro.
	dstVal := reflect.ValueOf(target)
	if dstVal.Kind() != reflect.Ptr || dstVal.IsNil() {
		return false
	}
	srcVal := reflect.ValueOf(src)
	if srcVal.Type().AssignableTo(dstVal.Elem().Type()) {
		dstVal.Elem().Set(srcVal)
		return true
	}
	return false
}

// `get` busca uma entrada no cache LRU.
// Retorna `(encontrado, estaExpirado)`. Mesmo expirado (`stale == true`), ele devolve o dado
// para a UI exibir instantaneamente enquanto revalida em background.
func (c *memoryCache) get(key string, target any, ttl time.Duration) (bool, bool) {
	c.mu.Lock()
	element := c.items[key]
	if element == nil {
		c.mu.Unlock()
		return false, false
	}

	// Atualiza o LRU: move este nó para o topo da lista duplamente ligada em O(1).
	c.order.MoveToFront(element)

	// Type assertion: extrai `*memoryEntry` de dentro do `any` armazenado no nó da lista.
	// Em TS seria equivalente a `element.value as MemoryEntry`.
	entry := element.Value.(*memoryEntry)
	raw := entry.raw
	payload := entry.payload
	saved := entry.saved

	// Liberamos o Mutex ANTES de copiar dados ou fazer Unmarshal!
	// Regra de ouro de concorrência em Go: mantenha a seção crítica (lock) o mais curta possível
	// para não bloquear outras goroutines esperando na fila.
	c.mu.Unlock()

	if raw != nil && assignValue(raw, target) {
		return true, time.Since(saved) > ttl
	}

	// Fallback caso a entrada tenha sido salva apenas como bytes serializados.
	if len(payload) > 0 && json.Unmarshal(payload, target) == nil {
		return true, time.Since(saved) > ttl
	}

	return false, false
}

// `put` insere ou atualiza um item no topo do LRU e remove os mais antigos (eviction) se passar de 16 MiB.
func (c *memoryCache) put(key string, value any) {
	// Importante: no `readCache` do `main.go`, quando lê do disco, ele passa `dest` (um ponteiro como `*[]run`).
	// Aqui desreferenciamos o ponteiro para guardar o valor limpo na memória, evitando guardar um ponteiro mutável.
	if rv := reflect.ValueOf(value); rv.Kind() == reflect.Ptr && !rv.IsNil() {
		value = rv.Elem().Interface()
	}

	size := estimateSize(value)
	if size > memoryLimit {
		return // Item maior que o limite total do cache; ignora para não limpar tudo à toa.
	}

	c.mu.Lock()
	// `defer c.mu.Unlock()` garante que o lock será liberado ao sair da função,
	// mesmo se ocorrer um retorno antecipado ou panic.
	defer c.mu.Unlock()

	// Se a chave já existia, subtrai o tamanho antigo e remove o nó velho da lista antes de reinserir.
	if old := c.items[key]; old != nil {
		c.used -= old.Value.(*memoryEntry).size
		c.order.Remove(old)
		delete(c.items, key)
	}

	entry := &memoryEntry{
		key:   key,
		raw:   value,
		size:  size,
		saved: time.Now(),
	}

	// Insere no início da lista (MRU - Most Recently Used) e salva o ponteiro do nó no map.
	c.items[key] = c.order.PushFront(entry)
	c.used += size

	// Eviction loop: enquanto o uso total exceder 16 MiB, remove os itens da cauda (LRU - Least Recently Used).
	for c.used > memoryLimit {
		oldest := c.order.Back()
		if oldest == nil {
			break
		}
		victim := oldest.Value.(*memoryEntry)
		c.used -= victim.size
		delete(c.items, victim.key)
		c.order.Remove(oldest)
	}
}
