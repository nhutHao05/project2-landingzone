'use client';

import { useEffect, useState } from 'react';

export default function CartButton({ label = 'Cart', className = 'cart-btn' }) {
  const [count, setCount] = useState(0);
  const isCart = label === 'Cart';

  useEffect(() => {
    if (!isCart) {
      return undefined;
    }

    const updateCount = () => setCount(current => current + 1);
    window.addEventListener('cybermart:add-to-cart', updateCount);

    return () => window.removeEventListener('cybermart:add-to-cart', updateCount);
  }, [isCart]);

  function handleClick() {
    if (isCart) {
      setCount(current => current + 1);
      return;
    }

    window.dispatchEvent(new Event('cybermart:add-to-cart'));
  }

  return (
    <button className={className} onClick={handleClick}>
      {isCart ? `Cart (${count})` : label}
    </button>
  );
}
