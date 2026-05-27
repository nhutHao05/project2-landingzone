'use client';

import { useState, useEffect } from 'react';

export default function Home() {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [cartCount, setCartCount] = useState(0);

  useEffect(() => {
    fetchProducts();
  }, []);

  const fetchProducts = async () => {
    try {
      const res = await fetch('/api/products');
      const data = await res.json();
      
      if (data.error) {
        if (data.error.includes('Table') && data.error.includes('does not exist')) {
          setError('DATABASE_NOT_INIT');
        } else {
          setError(data.error);
        }
      } else {
        setProducts(data.products || []);
        setError(null);
      }
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const initDatabase = async () => {
    setLoading(true);
    try {
      const res = await fetch('/api/init', { method: 'POST' });
      const data = await res.json();
      if (data.success) {
        await fetchProducts();
      } else {
        setError(data.error);
      }
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const addToCart = () => {
    setCartCount(prev => prev + 1);
  };

  return (
    <>
      <div className="ambient-bg"></div>
      
      <nav className="navbar">
        <div className="logo">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M12 2L2 7L12 12L22 7L12 2Z" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
            <path d="M2 17L12 22L22 17" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
            <path d="M2 12L12 17L22 12" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
          CyberMart
        </div>
        <button className="cart-btn">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"></path>
            <line x1="3" y1="6" x2="21" y2="6"></line>
            <path d="M16 10a4 4 0 0 1-8 0"></path>
          </svg>
          Cart
          {cartCount > 0 && <span className="cart-badge">{cartCount}</span>}
        </button>
      </nav>
      
      <main>
        <section className="hero">
          <div className="hero-badge">CyberMart 2.0 is Live</div>
          <h1>Upgrade Your Reality.</h1>
          <p>
            Discover next-generation cybernetic enhancements, holographic displays, and quantum computing devices engineered for the future.
          </p>
          <a href="#shop" className="hero-cta">Shop Collection</a>
        </section>

        <section id="shop" className="products-section">
          {error === 'DATABASE_NOT_INIT' && (
            <div className="init-alert">
              <div>
                <h3>System Offline</h3>
                <p>The product database needs to be initialized before shopping.</p>
              </div>
              <button onClick={initDatabase} className="init-btn">Initialize Database</button>
            </div>
          )}

          {error && error !== 'DATABASE_NOT_INIT' && (
            <div className="error-alert">
              ⚠️ Connection Error: {error}
            </div>
          )}

          <div className="section-header">
            <h2 className="section-title">Trending Now</h2>
          </div>

          {loading ? (
            <div className="loading-skeleton">
              {[1, 2, 3, 4].map(n => <div key={n} className="skeleton-card"></div>)}
            </div>
          ) : (
            <div className="grid">
              {products.map(product => (
                <article key={product.id} className="product-card">
                  <div className="product-image-wrapper">
                    {product.image_emoji || '📦'}
                  </div>
                  <div className="product-info">
                    <h3 className="product-title">{product.name}</h3>
                    <p className="product-desc">{product.description}</p>
                    <div className="product-footer">
                      <span className="price">${Number(product.price).toLocaleString('en-US', {minimumFractionDigits: 2})}</span>
                      <button onClick={addToCart} className="btn-add">Add</button>
                    </div>
                  </div>
                </article>
              ))}
            </div>
          )}
        </section>
      </main>
    </>
  );
}
