import http from 'k6/http';
import { sleep, check } from 'k6';

export const options = {
  scenarios: {
    gateway_ramp: {
      executor: 'ramping-arrival-rate',
      startRate: 5,
      timeUnit: '1s',
      preAllocatedVUs: 20,
      maxVUs: 100,
      stages: [
        { target: 20, duration: '30s' },
        { target: 60, duration: '60s' },
        { target: 5, duration: '20s' },
      ],
    },
  },
};

const domain = __ENV.APP_DOMAIN || 'mdp';
const target = __ENV.TARGET_URL || `http://gateway.${domain}/health`;

export default function () {
  const res = http.get(target);
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(0.2);
}
