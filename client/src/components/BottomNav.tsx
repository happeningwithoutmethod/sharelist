type NavItem = {
  id: string;
  label: string;
  icon: string;
  badge?: number;
};

export function BottomNav({
  items,
  active,
  onChange,
  label,
}: {
  items: readonly NavItem[];
  active: string;
  onChange: (id: string) => void;
  label: string;
}) {
  return (
    <nav className="bottom-nav" aria-label={label}>
      {items.map((item) => {
        const selected = active === item.id;
        return (
          <button
            key={item.id}
            type="button"
            className={selected ? 'active' : ''}
            aria-current={selected ? 'page' : undefined}
            onClick={() => onChange(item.id)}
          >
            <span className="nav-icon-wrap">
              {selected && <span className="nav-indicator" aria-hidden />}
              <span className="material-symbols-outlined" aria-hidden>
                {item.icon}
              </span>
              {item.badge != null && item.badge > 0 && (
                <span className="nav-badge">{item.badge > 99 ? '99+' : item.badge}</span>
              )}
            </span>
            <span className="nav-label">{item.label}</span>
          </button>
        );
      })}
    </nav>
  );
}
