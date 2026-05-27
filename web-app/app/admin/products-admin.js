'use client';

import { useEffect, useMemo, useState } from 'react';

const emptyForm = {
  name: '',
  description: '',
  price: '',
  image_label: 'TECH'
};

export default function AdminProducts() {
  const [products, setProducts] = useState([]);
  const [form, setForm] = useState(emptyForm);
  const [editingId, setEditingId] = useState(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  const formTitle = useMemo(() => editingId ? 'Edit Product' : 'Add Product', [editingId]);

  useEffect(() => {
    loadProducts();
  }, []);

  async function loadProducts() {
    setLoading(true);
    setError('');

    try {
      const response = await fetch('/api/products', { cache: 'no-store' });
      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.error || 'Unable to load products.');
      }

      setProducts(data.products || []);
    } catch (loadError) {
      setError(loadError.message);
    } finally {
      setLoading(false);
    }
  }

  function updateField(event) {
    const { name, value } = event.target;
    setForm(current => ({ ...current, [name]: value }));
  }

  function resetForm() {
    setEditingId(null);
    setForm(emptyForm);
    setMessage('');
    setError('');
  }

  function editProduct(product) {
    setEditingId(product.id);
    setForm({
      name: product.name,
      description: product.description || '',
      price: String(product.price),
      image_label: product.image_label || 'TECH'
    });
    setMessage('');
    setError('');
  }

  async function saveProduct(event) {
    event.preventDefault();
    setSaving(true);
    setMessage('');
    setError('');

    const method = editingId ? 'PUT' : 'POST';
    const url = editingId ? `/api/products/${editingId}` : '/api/products';

    try {
      const response = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(form)
      });
      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.error || 'Unable to save product.');
      }

      setMessage(editingId ? 'Product updated.' : 'Product created.');
      setEditingId(null);
      setForm(emptyForm);
      await loadProducts();
    } catch (saveError) {
      setError(saveError.message);
    } finally {
      setSaving(false);
    }
  }

  async function deleteProduct(product) {
    const confirmed = window.confirm(`Delete ${product.name}?`);

    if (!confirmed) {
      return;
    }

    setMessage('');
    setError('');

    try {
      const response = await fetch(`/api/products/${product.id}`, { method: 'DELETE' });
      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.error || 'Unable to delete product.');
      }

      if (editingId === product.id) {
        resetForm();
      }

      setProducts(current => current.filter(item => item.id !== product.id));
      setMessage('Product deleted.');
    } catch (deleteError) {
      setError(deleteError.message);
    }
  }

  return (
    <>
      <header>
        <h1>CyberMart Admin</h1>
        <nav className="top-nav">
          <a href="/">Store</a>
          <a href="/admin">Admin</a>
        </nav>
      </header>

      <main className="admin-layout">
        <section className="admin-panel">
          <h2>{formTitle}</h2>

          {message && <div className="success-alert">{message}</div>}
          {error && <div className="error-alert">{error}</div>}

          <form className="product-form" onSubmit={saveProduct}>
            <label>
              Name
              <input name="name" value={form.name} onChange={updateField} required maxLength="255" />
            </label>

            <label>
              Price
              <input name="price" type="number" min="0" step="0.01" value={form.price} onChange={updateField} required />
            </label>

            <label>
              Label
              <input name="image_label" value={form.image_label} onChange={updateField} maxLength="32" />
            </label>

            <label className="wide-field">
              Description
              <textarea name="description" value={form.description} onChange={updateField} rows="4" />
            </label>

            <div className="form-actions">
              <button className="init-btn" disabled={saving}>
                {saving ? 'Saving...' : 'Save'}
              </button>
              {editingId && (
                <button className="secondary-btn" type="button" onClick={resetForm}>
                  Cancel
                </button>
              )}
            </div>
          </form>
        </section>

        <section className="admin-panel">
          <h2>Products</h2>

          {loading ? (
            <p className="empty-state">Loading products...</p>
          ) : products.length === 0 ? (
            <p className="empty-state">No products yet.</p>
          ) : (
            <div className="table-wrap">
              <table className="product-table">
                <thead>
                  <tr>
                    <th>Name</th>
                    <th>Label</th>
                    <th>Price</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {products.map(product => (
                    <tr key={product.id}>
                      <td>
                        <strong>{product.name}</strong>
                        <span>{product.description}</span>
                      </td>
                      <td>{product.image_label}</td>
                      <td>${Number(product.price).toFixed(2)}</td>
                      <td>
                        <div className="row-actions">
                          <button className="secondary-btn" onClick={() => editProduct(product)}>Edit</button>
                          <button className="danger-btn" onClick={() => deleteProduct(product)}>Delete</button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </section>
      </main>
    </>
  );
}
