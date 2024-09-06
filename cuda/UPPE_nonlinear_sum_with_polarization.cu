#define MAX_NUM_MODES 32 // the maximum number of modes for this cuda = sqrt(MaxThreadsPerBlock)
                         //                                           = sqrt(1024) for our Titan XP GPU

__global__ void UPPE_nonlinear_sum_with_polarization(double2* Kerr, double2* Ra, double2* Rb, double2* Ra_sponRS, double2* Rb_sponRS,
                                                     const double2* At, const double2* At_noise,
                                                     const double* SK,  const unsigned char* SK_nonzero_midx1234s,  const unsigned int* SK_beginning_nonzero,  const unsigned int* SK_ending_nonzero,
                                                     const double* SRa, const unsigned char* SRa_nonzero_midx1234s, const unsigned int* SRa_beginning_nonzero, const unsigned int* SRa_ending_nonzero,
                                                     const double* SRb, const unsigned char* SRb_nonzero_midx1234s, const unsigned int* SRb_beginning_nonzero, const unsigned int* SRb_ending_nonzero,
                                                     const bool include_Raman, const bool include_anisoRaman,
                                                     const unsigned int N, const unsigned int M,
                                                     const unsigned int NUM_MODES,
                                                     const unsigned int NUM_OPERATIONS) {
    const unsigned int midx1 = threadIdx.x / NUM_MODES;
    const unsigned int midx2 = threadIdx.x - midx1*NUM_MODES;

    const unsigned int NMIdx = blockIdx.x / NUM_OPERATIONS;
    const unsigned int OPERATIONIdx = blockIdx.x - NMIdx*NUM_OPERATIONS;

    const unsigned int Midx = NMIdx / N;
    const unsigned int Nidx = NMIdx - Midx*N;

    const unsigned int NM = N*M;
    const unsigned int NMMODES = NM*NUM_MODES;

    // Preload At to improve the performance (avoiding accessing the global memory too many times)
    __shared__ double2 this_At[MAX_NUM_MODES], this_At_noise[MAX_NUM_MODES];
    switch (OPERATIONIdx) {
        case 0: // For Kerr interactions, noise photon is included directly for accurately computing noise-seeded processes
            if (midx1 == 0) {
                this_At[midx2].x = At[Nidx+Midx*N+midx2*NM].x + At_noise[Nidx+Midx*N+midx2*NM].x;
                this_At[midx2].y = At[Nidx+Midx*N+midx2*NM].y + At_noise[Nidx+Midx*N+midx2*NM].y;
            }
            break;
        case 1:
        case 2:
            if (midx1 == 0) this_At[midx2] = At[Nidx+Midx*N+midx2*NM];
            break;
        case 3:
        case 4:
            if (midx1 == 0) {
                this_At[midx2] = At[Nidx+Midx*N+midx2*NM];
                this_At_noise[midx2] = At_noise[Nidx+Midx*N+midx2*NM];
            }
            break;
    }
    __syncthreads();

    const unsigned int this_SK_beginning_nonzero = SK_beginning_nonzero[midx2+midx1*NUM_MODES];
    const unsigned int this_SK_ending_nonzero = SK_ending_nonzero[midx2+midx1*NUM_MODES];
    const unsigned int this_SRa_beginning_nonzero = SRa_beginning_nonzero[midx2+midx1*NUM_MODES];
    const unsigned int this_SRa_ending_nonzero = SRa_ending_nonzero[midx2+midx1*NUM_MODES];
    const unsigned int this_SRb_beginning_nonzero = SRb_beginning_nonzero[midx2+midx1*NUM_MODES];
    const unsigned int this_SRb_ending_nonzero = SRb_ending_nonzero[midx2+midx1*NUM_MODES];

    unsigned int midx3, midx4;
    double c, d, e, f;
    switch (OPERATIONIdx) {
        case 0: // compute the Kerr term
            if (this_SK_beginning_nonzero > 0) {
                double a, b, pcdef, ncdef;
                a = this_At[midx2].x;
                b = this_At[midx2].y;

                double2 this_Kerr;
                this_Kerr.x = 0; this_Kerr.y = 0; // initialized
                for (int i = this_SK_beginning_nonzero-1; i < this_SK_ending_nonzero-1; i++) {
                    midx3 = SK_nonzero_midx1234s[2+i*4]-1;
                    midx4 = SK_nonzero_midx1234s[3+i*4]-1;
            
                    c = this_At[midx3].x;
                    d = this_At[midx3].y;
                    e = this_At[midx4].x;
                    f = this_At[midx4].y;
            
                    pcdef = SK[i]*(c*e+d*f);
                    if (midx3 == midx4 || (int(midx3 & 1) != int(midx4 & 1)) ) {
                        if (midx3 == midx4) { // c=e, d=f --> ncdef=0
                            this_Kerr.x += a*pcdef;
                            this_Kerr.y += b*pcdef;
                        } else {
                            ncdef = SK[i]*(c*f-d*e);
                            this_Kerr.x += a*pcdef+b*ncdef;
                            this_Kerr.y += b*pcdef-a*ncdef;
                        }
                    } else { // (d*e-c*f) + (c <--> e, d <--> f) = 0
                        this_Kerr.x += a*pcdef*2;
                        this_Kerr.y += b*pcdef*2;
                    }
                }
                Kerr[Nidx+Midx*N+midx1*NM+midx2*NMMODES] = this_Kerr;
            }
            break;

        case 1: // compute the SRa tensors, isotropic Raman response
            if (include_Raman && this_SRa_beginning_nonzero > 0) {
                double2 this_Ra;
                this_Ra.x = 0; this_Ra.y = 0; // initialized
                for (int i = this_SRa_beginning_nonzero-1; i < this_SRa_ending_nonzero-1; i++) {
                    midx3 = SRa_nonzero_midx1234s[2+i*4]-1;
                    midx4 = SRa_nonzero_midx1234s[3+i*4]-1;
        
                    c = this_At[midx3].x;
                    d = this_At[midx3].y;
                    e = this_At[midx4].x;
                    f = this_At[midx4].y;
            
                    if (midx3 == midx4 || (int(midx3 & 1) != int(midx4 & 1)) ) {
                        if (midx3 == midx4) { // c=e, d=f
                            this_Ra.x += SRa[i]*(c*e+d*f);
                        } else {
                            this_Ra.x += SRa[i]*(c*e+d*f);
                            this_Ra.y += SRa[i]*(d*e-c*f);
                        }
                    } else { // (d*e-c*f) + (c <--> e, d <--> f) = 0
                        this_Ra.x += SRa[i]*(c*e+d*f)*2;
                    }
                }
                Ra[Nidx+Midx*N+midx1*NM+midx2*NMMODES] = this_Ra;
            }
            break;

        case 2: // compute the SRb tensors, anisotropic Raman response
            if ( (include_Raman && include_anisoRaman) && this_SRb_beginning_nonzero > 0) {
                double2 this_Rb;
                this_Rb.x = 0; this_Rb.y = 0; // initialized
                for (int i = this_SRb_beginning_nonzero-1; i < this_SRb_ending_nonzero-1; i++) {
                    midx3 = SRb_nonzero_midx1234s[2+i*4]-1;
                    midx4 = SRb_nonzero_midx1234s[3+i*4]-1;
        
                    c = this_At[midx3].x;
                    d = this_At[midx3].y;
                    e = this_At[midx4].x;
                    f = this_At[midx4].y;
        
                    if (midx3 == midx4 || (int(midx3 & 1) != int(midx4 & 1)) ) {
                        if (midx3 == midx4) { // c=e, d=f
                            this_Rb.x += SRb[i]*(c*e+d*f);
                        } else {
                            this_Rb.x += SRb[i]*(c*e+d*f);
                            this_Rb.y += SRb[i]*(d*e-c*f);
                        }
                    } else { // (d*e-c*f) + (c <--> e, d <--> f) = 0
                        this_Rb.x += SRb[i]*(c*e+d*f)*2;
                    }
                }
                Rb[Nidx+Midx*N+midx1*NM+midx2*NMMODES] = this_Rb;
            }
            break;

        case 3: // compute the spontaneous SRa tensors from the isotropic Raman response
            if (include_Raman && this_SRa_beginning_nonzero > 0) {
                double p, q, r, s; // this_At_noise
                double2 this_Ra_sponRS;
                this_Ra_sponRS.x = 0; this_Ra_sponRS.y = 0; // initialized
                for (int i = this_SRa_beginning_nonzero-1; i < this_SRa_ending_nonzero-1; i++) {
                    midx3 = SRa_nonzero_midx1234s[2+i*4]-1;
                    midx4 = SRa_nonzero_midx1234s[3+i*4]-1;
        
                    c = this_At[midx3].x;
                    d = this_At[midx3].y;
                    e = this_At[midx4].x;
                    f = this_At[midx4].y;

                    p = this_At_noise[midx3].x;
                    q = this_At_noise[midx3].y;
                    r = this_At_noise[midx4].x;
                    s = this_At_noise[midx4].y;
            
                    if (midx3 == midx4 || (int(midx3 & 1) != int(midx4 & 1)) ) {
                        if (midx3 == midx4) {
                            this_Ra_sponRS.x += SRa[i]*( (p*r+q*s) + (c*r+d*s)*2 );
                        } else {
                            this_Ra_sponRS.x += SRa[i]*( (p*r+q*s) + (c*r+d*s) + (p*e+q*f) );
                            this_Ra_sponRS.y += SRa[i]*( (q*r-p*s) + (d*r-c*s) + (q*e-p*f) );
                        }
                    } else {
                        this_Ra_sponRS.x += SRa[i]*( (p*r+q*s)*2 + (c*r+d*s)*2+(e*p+f*q)*2 );
                    }
                }
                Ra_sponRS[Nidx+Midx*N+midx1*NM+midx2*NMMODES] = this_Ra_sponRS;
            }
            break;

        case 4: // compute the spontaneous SRb tensors from the anisotropic Raman response
            if ( (include_Raman && include_anisoRaman) && this_SRb_beginning_nonzero > 0) {
                double p, q, r, s; // this_At_noise
                double2 this_Rb_sponRS;
                this_Rb_sponRS.x = 0; this_Rb_sponRS.y = 0; // initialized
                for (int i = this_SRb_beginning_nonzero-1; i < this_SRb_ending_nonzero-1; i++) {
                    midx3 = SRb_nonzero_midx1234s[2+i*4]-1;
                    midx4 = SRb_nonzero_midx1234s[3+i*4]-1;
        
                    c = this_At[midx3].x;
                    d = this_At[midx3].y;
                    e = this_At[midx4].x;
                    f = this_At[midx4].y;

                    p = this_At_noise[midx3].x;
                    q = this_At_noise[midx3].y;
                    r = this_At_noise[midx4].x;
                    s = this_At_noise[midx4].y;
        
                    if (midx3 == midx4 || (int(midx3 & 1) != int(midx4 & 1)) ) {
                        if (midx3 == midx4) {
                            this_Rb_sponRS.x += SRb[i]*( (p*r+q*s) + (c*r+d*s)*2 );
                        } else {
                            this_Rb_sponRS.x += SRb[i]*( (p*r+q*s) + (c*r+d*s) + (p*e+q*f) );
                            this_Rb_sponRS.y += SRb[i]*( (q*r-p*s) + (d*r-c*s) + (q*e-p*f) );
                        }
                    } else {
                        this_Rb_sponRS.x += SRb[i]*( (p*r+q*s)*2 + (c*r+d*s)*2+(e*p+f*q)*2 );
                    }
                }
                Rb_sponRS[Nidx+Midx*N+midx1*NM+midx2*NMMODES] = this_Rb_sponRS;
            }
            break;
    }
}
