# ShopMicro SLIs and SLOs

## Service Level Indicators (SLIs)
1. **API Error Rate (Availability)**: The proportion of valid HTTP requests to the backend API that return an HTTP 5xx error.
2. **API Latency (Performance)**: The duration (in milliseconds) it takes for the backend API to successfully respond to a valid HTTP request.
3. **ML Recommendation Delivery (Correctness/Availability)**: The proportion of successful `/recommendations` API hits that return valid recommendations within boundaries.

## Service Level Objectives (SLOs)
1. **API Error Rate SLO**: The backend API application must successfully fulfill 99.5% of valid requests (non-5xx responses) measured over a rolling 30-day window.
   - *Rationale*: For an e-commerce platform, absolute availability is critical but 99.9% might restrict deployment velocity for a small squad. 99.5% is a reasonable starting point prioritizing user experience.

2. **API Latency SLO**: The 95th percentile of response times for the backend API must be under 300ms measured over a rolling 7-day window.
   - *Rationale*: A slow checkout or product loading page impacts cart abandonment. Therefore, keeping 95% of traffic under 300ms guarantees a snappy feeling across the UI.
